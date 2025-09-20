import json
import os
from typing import Optional, List, Dict, Any
try:
    from app.schemas import MealParse, MealItem, MacroTotals
    from app.llm import claude_call
except ImportError:
    from backend.app.schemas import MealParse, MealItem, MacroTotals
    from backend.app.llm import claude_call

class VisionNutrition:
    def parse(self, image_url: str, hints: Optional[str] = None) -> MealParse:
        """
        Parse meal photo into items/macros using Claude Vision API.
        """
        system_prompt = """You are a nutrition expert analyzing food photos.
        Analyze the image and identify all food items with portions and nutritional information.

        IMPORTANT: If the image does not contain food or contains only non-food items (pets, objects, people, etc.),
        return an empty items array and set confidence to 0.0.

        Return ONLY valid JSON in this exact format with no additional text:
        {
          "items": [
            {
              "name": "food item name",
              "qty": numeric quantity,
              "unit": "g" or "ml" or "cup" etc,
              "kcal": calories as integer,
              "protein_g": protein in grams as number,
              "carbs_g": carbs in grams as number,
              "fat_g": fat in grams as number
            }
          ],
          "confidence": 0.0 to 1.0,
          "is_food": true or false
        }

        Estimate portion sizes from visual cues (plate size, utensils, etc).
        Be accurate with nutritional values based on typical preparations.
        Set is_food to false if no edible food items are detected.
        """
        
        user_message = [
            {
                "type": "text",
                "text": "Analyze this meal photo and provide nutritional breakdown."
            }
        ]
        
        # Add image to message
        if image_url.startswith("data:image"):
            # Base64 image
            media_type = image_url.split(";")[0].split(":")[1]
            base64_data = image_url.split(",")[1]
            user_message.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": media_type,
                    "data": base64_data
                }
            })
        else:
            # URL image - would need to fetch and convert to base64
            # For now, use fallback
            return self._fallback_vision_parse()
        
        if hints:
            user_message[0]["text"] += f"\nAdditional context: {hints}"
        
        try:
            # Call Claude Vision API
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-sonnet-20241022",  # Sonnet has better vision capabilities
                metadata={"tool": "vision_nutrition_parse"}
            )
            
            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"
            
            # Parse JSON
            try:
                if "```json" in response_text:
                    response_text = response_text.split("```json")[1].split("```")[0]
                elif "```" in response_text:
                    response_text = response_text.split("```")[1].split("```")[0]
                    
                data = json.loads(response_text)

                # Check if food was detected
                is_food = data.get("is_food", True)
                if not is_food or not data.get("items"):
                    # No food detected - return empty parse with low confidence
                    return MealParse(
                        items=[],
                        totals=MacroTotals(kcal=0, protein_g=0, carbs_g=0, fat_g=0),
                        confidence=0.0,
                        questions=["No food items detected in this image. Please try again with a clearer food photo."],
                        low_confidence=True
                    )

                # Convert to MealItem objects
                items = []
                for item_data in data.get("items", []):
                    items.append(
                        MealItem(
                            name=item_data.get("name", "unknown"),
                            qty=float(item_data.get("qty", 100)),
                            unit=item_data.get("unit", "g"),
                            kcal=int(item_data.get("kcal", 0)),
                            protein_g=float(item_data.get("protein_g", 0)),
                            carbs_g=float(item_data.get("carbs_g", 0)),
                            fat_g=float(item_data.get("fat_g", 0)),
                            fdc_id=None
                        )
                    )
                
                confidence = float(data.get("confidence", 0.7))
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Failed to parse Claude vision response: {e}")
                return self._fallback_vision_parse()
                
        except Exception as e:
            print(f"Claude Vision API call failed: {e}")
            
            # Check if it's a specific image processing error
            error_msg = str(e)
            if "Could not process image" in error_msg:
                print("Image processing failed - image may be too small, unclear, or corrupted")
            elif "Invalid image format" in error_msg:
                print("Image format not supported - try JPG or PNG format")
            elif "Image too large" in error_msg:
                print("Image file size too large - try compressing the image")
                
            return self._fallback_vision_parse()
        
        # Calculate totals
        totals = MacroTotals(
            kcal=sum(item.kcal for item in items),
            protein_g=sum(item.protein_g for item in items),
            carbs_g=sum(item.carbs_g for item in items),
            fat_g=sum(item.fat_g for item in items)
        )
        
        return MealParse(
            items=items,
            totals=totals,
            confidence=confidence,
            questions=["Can you confirm all items in the photo?"] if confidence < 0.7 else None,
            low_confidence=confidence < 0.6
        )
    
    def _fallback_vision_parse(self) -> MealParse:
        """Fallback when vision API is unavailable or can't identify food"""
        items = [
            MealItem(
                name="unidentified food from photo",
                qty=1,
                unit="serving",
                kcal=0,
                protein_g=0,
                carbs_g=0,
                fat_g=0,
                fdc_id=None
            )
        ]
        
        totals = MacroTotals(
            kcal=0,
            protein_g=0,
            carbs_g=0,
            fat_g=0
        )
        
        return MealParse(
            items=items,
            totals=totals,
            confidence=0.1,
            questions=[
                "Could not identify food from photo automatically.",
                "Please provide more details about what's in the image.",
                "Example: 'chicken breast with rice and vegetables' or 'large pepperoni pizza slice'"
            ],
            low_confidence=True
        )

class TextNutrition:
    def parse(self, text: str, hints: Optional[str] = None) -> MealParse:
        """
        Parse text meal into items/macros using Claude API.
        """
        # Build the prompt for Claude
        system_prompt = """You are a nutrition expert analyzing food descriptions.
        Parse the food text into individual items with accurate nutritional information.

        SPELLING & NAME CORRECTION:
        - Always correct misspelled food names to their proper form
        - Use standard, recognizable food names (e.g., "chiken" → "chicken", "bannana" → "banana")
        - Normalize food names to common variations (e.g., "mac n cheese" → "macaroni and cheese")
        - Fix obvious typos and provide the correct spelling in the output

        CRITICAL: Return ONLY valid JSON with no additional text, explanations, or markdown formatting.

        JSON Format:
        {
          "items": [
            {
              "name": "food item name",
              "qty": numeric quantity,
              "unit": "g" or "ml" or "slice" or "cup" etc,
              "kcal": total calories for the specified quantity,
              "protein_g": total protein for the specified quantity,
              "carbs_g": total carbs for the specified quantity,
              "fat_g": total fat for the specified quantity
            }
          ],
          "confidence": 0.0 to 1.0
        }

        QUANTITY UNDERSTANDING - Very Important:
        - Parse the EXACT quantity mentioned and calculate nutrition for that total amount
        - "1 slice pizza" = nutrition for 1 slice (~270 kcal)
        - "5 slices pizza" = nutrition for 5 slices (~1350 kcal total)
        - "half slice pizza" = nutrition for 0.5 slice (~135 kcal)
        - "2 cups rice" = nutrition for 2 cups total

        Examples:
        Input: "1 slice pizza" -> {"name": "pizza", "qty": 1, "unit": "slice", "kcal": 270, ...}
        Input: "5 slices pizza" -> {"name": "pizza", "qty": 5, "unit": "slice", "kcal": 1350, ...}
        Input: "2 eggs" -> {"name": "eggs", "qty": 2, "unit": "large", "kcal": 140, ...}

        Return ONLY the JSON object, no other text."""
        
        user_message = f"Parse this meal: {text}"
        if hints:
            user_message += f"\nAdditional context: {hints}"
        
        try:
            # Call Claude API with Sonnet for better instruction following
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-sonnet-20241022",  # Upgraded from Haiku for better quantity understanding
                metadata={"tool": "text_nutrition_parse", "text": text[:100]}
            )
            
            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"
            
            # Try to parse JSON
            try:
                # Debug logging to see what Claude actually returned
                print(f"🔍 Claude raw response length: {len(response_text)} chars")
                print(f"🔍 Claude response preview: {response_text[:200]}...")

                # Enhanced JSON extraction logic
                cleaned_text = response_text.strip()

                # Method 1: Look for markdown JSON blocks
                if "```json" in cleaned_text:
                    start = cleaned_text.find("```json") + 7
                    end = cleaned_text.find("```", start)
                    if end > start:
                        cleaned_text = cleaned_text[start:end].strip()
                        print("📝 Extracted from ```json block")
                elif "```" in cleaned_text:
                    start = cleaned_text.find("```") + 3
                    end = cleaned_text.find("```", start)
                    if end > start:
                        cleaned_text = cleaned_text[start:end].strip()
                        print("📝 Extracted from ``` block")

                # Method 2: Look for first { to last } for pure JSON
                if cleaned_text.startswith('{') and cleaned_text.count('{') > 0:
                    first_brace = cleaned_text.find('{')
                    last_brace = cleaned_text.rfind('}')
                    if last_brace > first_brace:
                        potential_json = cleaned_text[first_brace:last_brace + 1]
                        try:
                            # Test if this is valid JSON
                            test_data = json.loads(potential_json)
                            cleaned_text = potential_json
                            print("📝 Extracted JSON from braces")
                        except json.JSONDecodeError:
                            pass  # Keep original cleaned_text

                print(f"🔍 Cleaned JSON to parse: {cleaned_text[:100]}...")
                data = json.loads(cleaned_text)

                # Trust Claude Sonnet to handle quantities correctly
                print(f"🧠 Claude Sonnet parsed {len(data.get('items', []))} food items with quantities")

                # Convert to MealItem objects (no manual scaling needed)
                items = []
                for item_data in data.get("items", []):
                    name = item_data.get("name", "unknown")
                    qty = float(item_data.get("qty", 100))
                    unit = item_data.get("unit", "g")
                    kcal = int(item_data.get("kcal", 0))
                    protein_g = float(item_data.get("protein_g", 0))
                    carbs_g = float(item_data.get("carbs_g", 0))
                    fat_g = float(item_data.get("fat_g", 0))

                    print(f"🍕 {name}: {qty} {unit}, {kcal} kcal")

                    items.append(
                        MealItem(
                            name=name,
                            qty=qty,
                            unit=unit,
                            kcal=kcal,
                            protein_g=protein_g,
                            carbs_g=carbs_g,
                            fat_g=fat_g,
                            fdc_id=None
                        )
                    )

                confidence = float(data.get("confidence", 0.7))
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                # Enhanced error logging
                print(f"❌ Failed to parse Claude response: {e}")
                print(f"❌ Error type: {type(e).__name__}")
                print(f"❌ Raw response (first 500 chars): {response_text[:500]}")
                if hasattr(e, 'pos'):
                    error_pos = getattr(e, 'pos', 0)
                    print(f"❌ Error at position {error_pos}: '{response_text[max(0, error_pos-20):error_pos+20]}'")

                # Fallback if parsing fails
                print(f"🔄 Using fallback parser for text: '{text}'")
                items = self._fallback_parse(text)
                confidence = 0.5
                
        except Exception as e:
            print(f"Claude API call failed: {e}")
            # Use fallback parsing
            items = self._fallback_parse(text)
            confidence = 0.4
            
            # If fallback returns unrecognized food, set very low confidence
            if items and items[0].name == "unrecognized food":
                confidence = 0.1
        
        # Calculate totals
        totals = MacroTotals(
            kcal=sum(item.kcal for item in items),
            protein_g=sum(item.protein_g for item in items),
            carbs_g=sum(item.carbs_g for item in items),
            fat_g=sum(item.fat_g for item in items)
        )
        
        # Generate appropriate questions based on confidence and food type
        questions = []
        if confidence < 0.2:
            questions = [
                "Could not recognize this food automatically.",
                "Please provide more details like portion size or specific food type.",
                "Example: 'large pepperoni pizza slice' or 'grilled chicken breast 200g'"
            ]
        elif confidence < 0.6:
            if items and items[0].name != "unrecognized food":
                questions = [f"Is this the correct food: {items[0].name}?", "Any sides, sauces, or additional items?"]
            else:
                questions = ["Please provide more specific food details for better accuracy."]
        elif confidence < 0.8:
            questions = ["Was this the complete meal? Any sides or drinks?"]
        
        return MealParse(
            items=items,
            totals=totals,
            confidence=confidence,
            questions=questions,
            low_confidence=confidence < 0.6
        )
    
    def _fallback_parse(self, text: str) -> List[MealItem]:
        """Enhanced fallback parser with comprehensive food database"""
        text_lower = text.lower()
        items = []
        
        # Comprehensive food database with accurate nutrition data
        food_db = {
            # Proteins
            "chicken breast": {"qty": 100, "unit": "g", "kcal": 165, "protein_g": 31, "carbs_g": 0, "fat_g": 3.6},
            "chicken thigh": {"qty": 100, "unit": "g", "kcal": 209, "protein_g": 26, "carbs_g": 0, "fat_g": 11},
            "salmon": {"qty": 100, "unit": "g", "kcal": 208, "protein_g": 20, "carbs_g": 0, "fat_g": 13},
            "tuna": {"qty": 100, "unit": "g", "kcal": 132, "protein_g": 28, "carbs_g": 0, "fat_g": 1},
            "beef": {"qty": 100, "unit": "g", "kcal": 250, "protein_g": 26, "carbs_g": 0, "fat_g": 15},
            "pork": {"qty": 100, "unit": "g", "kcal": 242, "protein_g": 27, "carbs_g": 0, "fat_g": 14},
            "turkey": {"qty": 100, "unit": "g", "kcal": 135, "protein_g": 30, "carbs_g": 0, "fat_g": 1},
            "egg": {"qty": 50, "unit": "g", "kcal": 78, "protein_g": 6, "carbs_g": 0.6, "fat_g": 5},
            "tofu": {"qty": 100, "unit": "g", "kcal": 76, "protein_g": 8, "carbs_g": 2, "fat_g": 5},
            
            # Carbs & Grains
            "rice": {"qty": 158, "unit": "g", "kcal": 206, "protein_g": 4.3, "carbs_g": 45, "fat_g": 0.4},
            "brown rice": {"qty": 158, "unit": "g", "kcal": 216, "protein_g": 5, "carbs_g": 45, "fat_g": 1.8},
            "pasta": {"qty": 140, "unit": "g", "kcal": 220, "protein_g": 8, "carbs_g": 43, "fat_g": 1.3},
            "quinoa": {"qty": 185, "unit": "g", "kcal": 222, "protein_g": 8, "carbs_g": 39, "fat_g": 3.6},
            "oatmeal": {"qty": 234, "unit": "g", "kcal": 154, "protein_g": 6, "carbs_g": 27, "fat_g": 3},
            "bread": {"qty": 28, "unit": "g", "kcal": 79, "protein_g": 2.3, "carbs_g": 14, "fat_g": 1},
            "bagel": {"qty": 95, "unit": "g", "kcal": 245, "protein_g": 10, "carbs_g": 48, "fat_g": 1.5},
            "tortilla": {"qty": 30, "unit": "g", "kcal": 94, "protein_g": 2.5, "carbs_g": 15, "fat_g": 2.5},
            
            # Pizza & Fast Food  
            "pizza": {"qty": 107, "unit": "g", "kcal": 266, "protein_g": 11, "carbs_g": 33, "fat_g": 10},
            "pizza slice": {"qty": 107, "unit": "g", "kcal": 266, "protein_g": 11, "carbs_g": 33, "fat_g": 10},
            "pepperoni pizza": {"qty": 107, "unit": "g", "kcal": 298, "protein_g": 13, "carbs_g": 36, "fat_g": 12},
            "burger": {"qty": 150, "unit": "g", "kcal": 295, "protein_g": 17, "carbs_g": 24, "fat_g": 14},
            "cheeseburger": {"qty": 154, "unit": "g", "kcal": 335, "protein_g": 17, "carbs_g": 33, "fat_g": 15},
            "fries": {"qty": 115, "unit": "g", "kcal": 365, "protein_g": 4, "carbs_g": 48, "fat_g": 17},
            "hot dog": {"qty": 98, "unit": "g", "kcal": 290, "protein_g": 11, "carbs_g": 24, "fat_g": 17},
            
            # Fruits
            "apple": {"qty": 182, "unit": "g", "kcal": 95, "protein_g": 0.5, "carbs_g": 25, "fat_g": 0.3},
            "banana": {"qty": 118, "unit": "g", "kcal": 105, "protein_g": 1.3, "carbs_g": 27, "fat_g": 0.4},
            "orange": {"qty": 154, "unit": "g", "kcal": 62, "protein_g": 1.2, "carbs_g": 15, "fat_g": 0.2},
            "strawberries": {"qty": 152, "unit": "g", "kcal": 49, "protein_g": 1, "carbs_g": 12, "fat_g": 0.5},
            "grapes": {"qty": 92, "unit": "g", "kcal": 62, "protein_g": 0.6, "carbs_g": 16, "fat_g": 0.2},
            
            # Vegetables
            "broccoli": {"qty": 91, "unit": "g", "kcal": 31, "protein_g": 2.6, "carbs_g": 6, "fat_g": 0.3},
            "spinach": {"qty": 30, "unit": "g", "kcal": 7, "protein_g": 0.9, "carbs_g": 1, "fat_g": 0.1},
            "carrots": {"qty": 128, "unit": "g", "kcal": 52, "protein_g": 1.2, "carbs_g": 12, "fat_g": 0.3},
            "salad": {"qty": 200, "unit": "g", "kcal": 35, "protein_g": 2, "carbs_g": 7, "fat_g": 0.5},
            "tomato": {"qty": 180, "unit": "g", "kcal": 32, "protein_g": 1.6, "carbs_g": 7, "fat_g": 0.4},
            
            # Dairy
            "milk": {"qty": 244, "unit": "ml", "kcal": 146, "protein_g": 8, "carbs_g": 11, "fat_g": 8},
            "yogurt": {"qty": 245, "unit": "g", "kcal": 149, "protein_g": 9, "carbs_g": 12, "fat_g": 8},
            "greek yogurt": {"qty": 170, "unit": "g", "kcal": 100, "protein_g": 17, "carbs_g": 6, "fat_g": 0},
            "cheese": {"qty": 28, "unit": "g", "kcal": 113, "protein_g": 7, "carbs_g": 0.4, "fat_g": 9},
            
            # Snacks & Desserts
            "chips": {"qty": 28, "unit": "g", "kcal": 152, "protein_g": 2, "carbs_g": 15, "fat_g": 10},
            "cookies": {"qty": 25, "unit": "g", "kcal": 120, "protein_g": 1.5, "carbs_g": 17, "fat_g": 5},
            "chocolate": {"qty": 28, "unit": "g", "kcal": 155, "protein_g": 2, "carbs_g": 17, "fat_g": 9},
            "ice cream": {"qty": 66, "unit": "g", "kcal": 137, "protein_g": 2.3, "carbs_g": 16, "fat_g": 7},
            
            # Beverages
            "coffee": {"qty": 240, "unit": "ml", "kcal": 2, "protein_g": 0.3, "carbs_g": 0, "fat_g": 0},
            "soda": {"qty": 355, "unit": "ml", "kcal": 139, "protein_g": 0, "carbs_g": 39, "fat_g": 0},
            "beer": {"qty": 355, "unit": "ml", "kcal": 154, "protein_g": 1.6, "carbs_g": 13, "fat_g": 0},
            "wine": {"qty": 147, "unit": "ml", "kcal": 123, "protein_g": 0.1, "carbs_g": 4, "fat_g": 0},
            
            # International Foods
            "sushi": {"qty": 100, "unit": "g", "kcal": 142, "protein_g": 6, "carbs_g": 21, "fat_g": 4},
            "tacos": {"qty": 100, "unit": "g", "kcal": 226, "protein_g": 13, "carbs_g": 18, "fat_g": 12},
            "burrito": {"qty": 219, "unit": "g", "kcal": 298, "protein_g": 13, "carbs_g": 36, "fat_g": 12},
            "ramen": {"qty": 250, "unit": "g", "kcal": 188, "protein_g": 5, "carbs_g": 27, "fat_g": 7},
            "pad thai": {"qty": 400, "unit": "g", "kcal": 429, "protein_g": 17, "carbs_g": 64, "fat_g": 13}
        }
        
        # Detect portion size modifiers
        portion_multipliers = self._detect_portion_size(text_lower)
        
        # Check for known foods with better matching
        found_any = False
        for food_name, base_nutrition in food_db.items():
            if self._food_matches(food_name, text_lower):
                # Apply portion size adjustment
                nutrition = base_nutrition.copy()
                multiplier = portion_multipliers.get('general', 1.0)
                
                # Special handling for pizza slices
                if 'pizza' in food_name and any(word in text_lower for word in ['large', 'big']):
                    multiplier = 1.5
                elif 'pizza' in food_name and any(word in text_lower for word in ['small', 'thin']):
                    multiplier = 0.7
                
                # Apply multiplier to all nutritional values
                for key in ['qty', 'kcal', 'protein_g', 'carbs_g', 'fat_g']:
                    if key == 'qty':
                        nutrition[key] = nutrition[key] * multiplier
                    else:
                        nutrition[key] = round(nutrition[key] * multiplier, 1)
                
                items.append(
                    MealItem(
                        name=f"{food_name}" + (" (large)" if multiplier > 1.2 else " (small)" if multiplier < 0.8 else ""),
                        unit=nutrition['unit'],
                        fdc_id=None,
                        **{k: v for k, v in nutrition.items() if k != 'unit'}
                    )
                )
                found_any = True
                break  # Only match first food found
        
        # If nothing found, return a helpful "unknown food" response
        if not found_any:
            items.append(
                MealItem(
                    name="unrecognized food",
                    qty=1,
                    unit="serving",
                    kcal=0,  # Set to 0 to indicate unknown
                    protein_g=0,
                    carbs_g=0,
                    fat_g=0,
                    fdc_id=None
                )
            )
        
        return items
    
    def _detect_portion_size(self, text: str) -> dict:
        """Detect portion size indicators in text"""
        import re

        multipliers = {'general': 1.0}

        # Debug logging to trace quantity detection
        print(f"🔢 Analyzing text for quantities: '{text}'")

        # Size indicators (should not override quantity-based multipliers)
        size_multiplier = 1.0
        if any(word in text for word in ['large', 'big', 'huge', 'jumbo', 'xl']):
            size_multiplier = 1.4
            print(f"📏 Size modifier detected: large (×{size_multiplier})")
        elif any(word in text for word in ['small', 'little', 'mini', 'tiny', 'xs']):
            size_multiplier = 0.7
            print(f"📏 Size modifier detected: small (×{size_multiplier})")
        elif any(word in text for word in ['medium', 'regular', 'normal']):
            size_multiplier = 1.0
            print(f"📏 Size modifier detected: medium (×{size_multiplier})")

        # Enhanced quantity detection using regex and word mapping
        quantity_multiplier = 1.0

        # Word-to-number mapping
        word_to_num = {
            'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
            'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
            'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
            'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
            'half': 0.5, 'quarter': 0.25, 'double': 2, 'triple': 3
        }

        # Check for word-based quantities
        for word, num in word_to_num.items():
            if word in text.lower():
                quantity_multiplier = num
                print(f"🔢 Word quantity detected: '{word}' = ×{quantity_multiplier}")
                break

        # Check for digit-based quantities (1-20)
        # Look for patterns like "5 slices", "10 pieces", etc.
        digit_match = re.search(r'\b(\d+(?:\.\d+)?)\s*(?:slice|piece|serving|portion|cup|item)', text.lower())
        if digit_match:
            quantity_multiplier = float(digit_match.group(1))
            print(f"🔢 Digit quantity detected: {quantity_multiplier}")
        elif re.search(r'\b(\d+(?:\.\d+)?)\s', text):
            # Fallback: any number followed by space
            number_match = re.search(r'\b(\d+(?:\.\d+)?)\s', text)
            if number_match:
                potential_qty = float(number_match.group(1))
                # Only use if it's a reasonable quantity (1-20)
                if 0.1 <= potential_qty <= 20:
                    quantity_multiplier = potential_qty
                    print(f"🔢 Fallback quantity detected: {quantity_multiplier}")

        # Fractional quantities
        if 'half' in text or '0.5' in text:
            quantity_multiplier = 0.5
            print(f"🔢 Fractional quantity detected: half = ×{quantity_multiplier}")
        elif '1.5' in text or 'one and a half' in text:
            quantity_multiplier = 1.5
            print(f"🔢 Fractional quantity detected: 1.5 = ×{quantity_multiplier}")

        # Combine size and quantity multipliers
        final_multiplier = quantity_multiplier * size_multiplier
        multipliers['general'] = final_multiplier

        print(f"🎯 Final multiplier: {quantity_multiplier} (qty) × {size_multiplier} (size) = {final_multiplier}")

        return multipliers
    
    def _food_matches(self, food_name: str, text: str) -> bool:
        """Enhanced food matching logic"""
        # Direct match
        if food_name in text:
            return True
        
        # Check for plural forms
        if food_name + 's' in text:
            return True
            
        # Check for common variations
        variations = {
            'pizza': ['pie', 'za'],
            'fries': ['french fries', 'chips'],
            'soda': ['soft drink', 'pop', 'coke'],
            'burger': ['hamburger', 'cheeseburger'],
        }
        
        if food_name in variations:
            return any(variant in text for variant in variations[food_name])
            
        return False

    def fix_parse(self, original_parse: 'MealParse', fix_prompt: str) -> 'MealParse':
        """Fix/re-parse meal analysis using AI with user feedback."""

        # Build context from original parse
        original_items = []
        for item in original_parse.items:
            original_items.append({
                "name": item.name,
                "qty": item.qty,
                "unit": item.unit,
                "kcal": item.kcal,
                "protein_g": item.protein_g,
                "carbs_g": item.carbs_g,
                "fat_g": item.fat_g
            })

        system_prompt = """You are a nutrition expert fixing meal analysis based on user feedback.
        The user provided feedback about what's wrong with the original analysis.
        Please provide a corrected analysis based on their input.

        Return ONLY valid JSON in this exact format with no additional text:
        {
          "items": [
            {
              "name": "food item name",
              "qty": numeric quantity,
              "unit": "g" or "ml" or "cup" etc,
              "kcal": calories as integer,
              "protein_g": protein in grams as number,
              "carbs_g": carbs in grams as number,
              "fat_g": fat in grams as number
            }
          ],
          "confidence": 0.0 to 1.0
        }

        Fix the issues mentioned by the user while maintaining nutritional accuracy.
        If portions need adjustment, scale all macros proportionally.
        """

        user_message = f"""Original analysis:
{json.dumps(original_items, indent=2)}

User feedback: {fix_prompt}

Please provide the corrected meal analysis addressing the user's concerns."""

        try:
            # Call Claude API
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-sonnet-20241022",
                metadata={"tool": "fix_nutrition_parse", "fix_prompt": fix_prompt[:100]}
            )

            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"

            # Parse JSON
            try:
                if "```json" in response_text:
                    response_text = response_text.split("```json")[1].split("```")[0]
                elif "```" in response_text:
                    response_text = response_text.split("```")[1].split("```")[0]

                data = json.loads(response_text)

                # Convert to MealItem objects
                items = []
                for item_data in data.get("items", []):
                    items.append(
                        MealItem(
                            name=item_data.get("name", "unknown"),
                            qty=float(item_data.get("qty", 100)),
                            unit=item_data.get("unit", "g"),
                            kcal=int(item_data.get("kcal", 0)),
                            protein_g=float(item_data.get("protein_g", 0)),
                            carbs_g=float(item_data.get("carbs_g", 0)),
                            fat_g=float(item_data.get("fat_g", 0)),
                            fdc_id=None
                        )
                    )

                # Calculate totals
                totals = MacroTotals(
                    kcal=sum(item.kcal for item in items),
                    protein_g=sum(item.protein_g for item in items),
                    carbs_g=sum(item.carbs_g for item in items),
                    fat_g=sum(item.fat_g for item in items)
                )

                confidence = data.get("confidence", 0.8)  # Higher confidence for corrections

                return MealParse(
                    items=items,
                    totals=totals,
                    confidence=confidence,
                    questions=[],
                    low_confidence=confidence < 0.6
                )

            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Failed to parse Claude fix response: {e}")
                # Return original parse if fix fails
                return original_parse

        except Exception as e:
            print(f"Claude API call failed for fix: {e}")
            # Return original parse if fix fails
            return original_parse

vision_nutrition = VisionNutrition()
text_nutrition = TextNutrition()

def _simple_spell_correct(food_name: str) -> str:
    """Simple spell correction for common food misspellings"""
    corrections = {
        # Common food spelling errors
        'chiken': 'chicken',
        'chikken': 'chicken',
        'chickn': 'chicken',
        'bannana': 'banana',
        'bananna': 'banana',
        'bannanas': 'bananas',
        'tomatoe': 'tomato',
        'tomatos': 'tomatoes',
        'potatoe': 'potato',
        'potatos': 'potatoes',
        'brocoli': 'broccoli',
        'brocolli': 'broccoli',
        'cabage': 'cabbage',
        'cabage': 'cabbage',
        'letuce': 'lettuce',
        'lettuece': 'lettuce',
        'cukumber': 'cucumber',
        'cumcumber': 'cucumber',
        'straberry': 'strawberry',
        'strawbery': 'strawberry',
        'blueberry': 'blueberry',
        'bluberry': 'blueberry',
        'rasberry': 'raspberry',
        'raspbery': 'raspberry',
        'oragne': 'orange',
        'ornage': 'orange',
        'appeL': 'apple',
        'aple': 'apple',
        'aplle': 'apple',
        'pineaple': 'pineapple',
        'pinnapple': 'pineapple',
        'avacado': 'avocado',
        'avacodo': 'avocado',
        'avadaco': 'avocado',
        'mushroom': 'mushroom',
        'mushromm': 'mushroom',
        'mushrrom': 'mushroom',
        'onoin': 'onion',
        'oinion': 'onion',
        'carrit': 'carrot',
        'carret': 'carrot',
        'carot': 'carrot',
        'celery': 'celery',
        'celer': 'celery',
        'celry': 'celery',
        'spinage': 'spinach',
        'spinich': 'spinach',
        'kale': 'kale',
        'kal': 'kale',
        'raddish': 'radish',
        'radish': 'radish',
        'beaf': 'beef',
        'bef': 'beef',
        'prok': 'pork',
        'prk': 'pork',
        'lam': 'lamb',
        'lamb': 'lamb',
        'fish': 'fish',
        'fsh': 'fish',
        'salmin': 'salmon',
        'samon': 'salmon',
        'tuna': 'tuna',
        'tna': 'tuna',
        'shrimp': 'shrimp',
        'shimp': 'shrimp',
        'shrmp': 'shrimp',
        'crab': 'crab',
        'carb': 'crab',
        'lobster': 'lobster',
        'lobstr': 'lobster',
        'rie': 'rice',
        'rce': 'rice',
        'ric': 'rice',
        'pasta': 'pasta',
        'psta': 'pasta',
        'noodels': 'noodles',
        'noodls': 'noodles',
        'noddles': 'noodles',
        'bred': 'bread',
        'brad': 'bread',
        'brd': 'bread',
        'toste': 'toast',
        'tost': 'toast',
        'tos': 'toast',
        'cerel': 'cereal',
        'cerial': 'cereal',
        'ceral': 'cereal',
        'oatemeal': 'oatmeal',
        'otmeal': 'oatmeal',
        'oatmel': 'oatmeal',
        'yougurt': 'yogurt',
        'yoghurt': 'yogurt',
        'yogrt': 'yogurt',
        'chese': 'cheese',
        'chees': 'cheese',
        'ches': 'cheese',
        'mlik': 'milk',
        'milc': 'milk',
        'mlk': 'milk',
        'buter': 'butter',
        'butr': 'butter',
        'buttr': 'butter',
        'eg': 'egg',
        'egs': 'eggs',
        'egss': 'eggs',
        'cofee': 'coffee',
        'coffe': 'coffee',
        'cofe': 'coffee',
        'te': 'tea',
        'tee': 'tea',
        'wat': 'water',
        'watr': 'water',
        'wter': 'water',
        'juce': 'juice',
        'juic': 'juice',
        'jucie': 'juice',
        'soda': 'soda',
        'soda': 'soda',
        'cooke': 'cookie',
        'cooki': 'cookie',
        'ckie': 'cookie',
        'cak': 'cake',
        'cke': 'cake',
        'pie': 'pie',
        'pi': 'pie',
        'iccream': 'ice cream',
        'icecream': 'ice cream',
        'ice crem': 'ice cream',
        'chocalate': 'chocolate',
        'chocolate': 'chocolate',
        'chocolat': 'chocolate',
        'choclate': 'chocolate',
        'chocolte': 'chocolate',
        'candey': 'candy',
        'candi': 'candy',
        'cady': 'candy',
        'nuts': 'nuts',
        'nut': 'nut',
        'almon': 'almond',
        'almnd': 'almond',
        'walut': 'walnut',
        'walnt': 'walnut',
        'penut': 'peanut',
        'peantu': 'peanut',
        'peant': 'peanut',
        'cashew': 'cashew',
        'cashw': 'cashew',
        'pican': 'pecan',
        'pecan': 'pecan',
        'hzelnut': 'hazelnut',
        'hazelnt': 'hazelnut',
        'pistachio': 'pistachio',
        'pistacio': 'pistachio',
        'macaroni': 'macaroni',
        'macroni': 'macaroni',
        'mac n cheese': 'macaroni and cheese',
        'mac and cheese': 'macaroni and cheese',
        'pizza': 'pizza',
        'piza': 'pizza',
        'pzza': 'pizza',
        'pizze': 'pizza',
        'burgr': 'burger',
        'burger': 'burger',
        'hambrger': 'hamburger',
        'hamburger': 'hamburger',
        'hotdog': 'hot dog',
        'hot dog': 'hot dog',
        'hotdg': 'hot dog',
        'sandwch': 'sandwich',
        'sandwhich': 'sandwich',
        'sandwitch': 'sandwich',
        'sandwi': 'sandwich',
        'sanwich': 'sandwich',
        'taco': 'taco',
        'tako': 'taco',
        'tcos': 'tacos',
        'tacoz': 'tacos',
        'burito': 'burrito',
        'buritto': 'burrito',
        'burito': 'burrito',
        'nachoes': 'nachos',
        'nachoss': 'nachos',
        'nacho': 'nachos',
        'quesadila': 'quesadilla',
        'quesadilla': 'quesadilla',
        'ques': 'quesadilla',
        'torila': 'tortilla',
        'tortila': 'tortilla',
        'tortilla': 'tortilla',
        'salsa': 'salsa',
        'salse': 'salsa',
        'guacamole': 'guacamole',
        'guac': 'guacamole',
        'guacamol': 'guacamole',
        'guacomole': 'guacamole',
        'soup': 'soup',
        'sou': 'soup',
        'sup': 'soup',
        'salad': 'salad',
        'sald': 'salad',
        'salda': 'salad',
        'caeser': 'caesar',
        'caesar': 'caesar',
        'cesar': 'caesar',
        'ceaser': 'caesar',
        'dressing': 'dressing',
        'dresing': 'dressing',
        'dressin': 'dressing',
        'oil': 'oil',
        'ol': 'oil',
        'vinegar': 'vinegar',
        'vinegr': 'vinegar',
        'vineagr': 'vinegar',
        'salt': 'salt',
        'slt': 'salt',
        'pepr': 'pepper',
        'pepper': 'pepper',
        'peppr': 'pepper',
        'sugar': 'sugar',
        'sugr': 'sugar',
        'suger': 'sugar',
        'honey': 'honey',
        'hony': 'honey',
        'hney': 'honey',
        'syrup': 'syrup',
        'sirup': 'syrup',
        'syrp': 'syrup',
        'jam': 'jam',
        'jem': 'jam',
        'jm': 'jam',
        'jelly': 'jelly',
        'jely': 'jelly',
        'jly': 'jelly',
        'pnut butter': 'peanut butter',
        'peanut butr': 'peanut butter',
        'peanut buter': 'peanut butter',
        'pb': 'peanut butter',
        'crackers': 'crackers',
        'crakers': 'crackers',
        'crackrs': 'crackers',
        'chips': 'chips',
        'chps': 'chips',
        'chipes': 'chips',
        'popcorn': 'popcorn',
        'popcor': 'popcorn',
        'popcm': 'popcorn',
        'pretzels': 'pretzels',
        'pretzls': 'pretzels',
        'pretzel': 'pretzel',
        'granola': 'granola',
        'granole': 'granola',
        'granla': 'granola',
        'beans': 'beans',
        'bens': 'beans',
        'benas': 'beans',
        'benas': 'beans',
        'lentils': 'lentils',
        'lentls': 'lentils',
        'lentis': 'lentils',
        'chikpeas': 'chickpeas',
        'chickpes': 'chickpeas',
        'chickpas': 'chickpeas',
        'chickpease': 'chickpeas',
        'hummus': 'hummus',
        'hmus': 'hummus',
        'humus': 'hummus',
        'hummas': 'hummus',
        'quinoa': 'quinoa',
        'quinoe': 'quinoa',
        'quinao': 'quinoa',
        'qinoa': 'quinoa',
        'tofu': 'tofu',
        'tofu': 'tofu',
        'tofu': 'tofu',
        'tempe': 'tempeh',
        'tempeh': 'tempeh',
        'seitan': 'seitan',
        'setan': 'seitan',
        'mushrooms': 'mushrooms',
        'mushroms': 'mushrooms',
        'mushroomz': 'mushrooms',
        'mushrms': 'mushrooms'
    }

    # Split into words and correct each
    words = food_name.lower().split()
    corrected_words = []

    for word in words:
        # Remove punctuation for comparison
        clean_word = word.strip('.,!?;:')
        if clean_word in corrections:
            corrected_words.append(corrections[clean_word])
        else:
            corrected_words.append(word)

    # Join back and capitalize properly
    corrected = ' '.join(corrected_words)
    return corrected.title() if corrected else food_name

def fix_meal_parse(original_parse: MealParse, fix_prompt: str) -> tuple[MealParse, list[str]]:
    """
    Fix or correct a meal parse based on user's natural language description.
    Returns updated parse and list of changes applied.
    """
    # Use the existing fix_parse method from TextNutrition
    fixed_parse = text_nutrition.fix_parse(original_parse, fix_prompt)
    changes_applied = ["AI corrections applied based on your feedback"]
    return fixed_parse, changes_applied

def fix_item(original_item: MealItem, fix_prompt: str, meal_context: list[MealItem] = None) -> tuple[MealItem, list[str]]:
    """
    Fix or correct a single meal item based on user's natural language description.
    Returns updated item and list of changes applied.
    """
    # Create a temporary meal parse with just this item for fixing
    temp_parse = MealParse(
        items=[original_item],
        totals=MacroTotals(
            kcal=original_item.kcal,
            protein_g=original_item.protein_g,
            carbs_g=original_item.carbs_g,
            fat_g=original_item.fat_g
        ),
        confidence=0.8,
        questions=None,
        low_confidence=False
    )

    # Add context about other items if provided
    context_info = ""
    if meal_context:
        other_items = [item.name for item in meal_context if item.name != original_item.name]
        if other_items:
            context_info = f" (This is part of a meal with: {', '.join(other_items)})"

    # Use the fix_parse method with context
    full_prompt = f"Fix this food item: {fix_prompt}{context_info}"
    fixed_parse = text_nutrition.fix_parse(temp_parse, full_prompt)

    # Extract the fixed item
    if fixed_parse.items:
        updated_item = fixed_parse.items[0]
        changes_applied = [f"Updated {original_item.name} based on your feedback"]
        return updated_item, changes_applied
    else:
        # Fallback if parsing failed
        return original_item, ["No changes could be applied"]

def add_food_item(food_description: str, existing_items: list[MealItem] = None) -> MealItem:
    """
    Parse a natural language food description into a meal item.
    Uses context from existing items for better accuracy.
    """
    try:
        # Add context about existing meal if provided
        context_info = ""
        if existing_items:
            existing_names = [item.name for item in existing_items]
            context_info = f" (Adding to existing meal with: {', '.join(existing_names)})"

        # Parse the food description with context
        full_description = f"{food_description}{context_info}"
        parsed = text_nutrition.parse(full_description)

        # Extract the first item (should be the new food)
        if parsed.items:
            return parsed.items[0]
        else:
            raise Exception("No items parsed")

    except Exception as e:
        print(f"Failed to parse food item '{food_description}': {e}")
        # Fallback: create a simple item based on the description with spell correction
        corrected_name = _simple_spell_correct(food_description.strip())

        # Simple heuristics for basic nutrition estimates
        name_lower = corrected_name.lower()
        if any(word in name_lower for word in ['salad', 'lettuce', 'greens']):
            return MealItem(name=corrected_name, qty=1, unit="serving", kcal=50, protein_g=2, carbs_g=8, fat_g=1, fdc_id=None)
        elif any(word in name_lower for word in ['bread', 'roll', 'toast']):
            return MealItem(name=corrected_name, qty=1, unit="slice", kcal=80, protein_g=3, carbs_g=15, fat_g=1, fdc_id=None)
        elif any(word in name_lower for word in ['cookie', 'cake', 'dessert']):
            return MealItem(name=corrected_name, qty=1, unit="piece", kcal=150, protein_g=2, carbs_g=20, fat_g=7, fdc_id=None)
        elif any(word in name_lower for word in ['fries', 'chips']):
            return MealItem(name=corrected_name, qty=1, unit="serving", kcal=200, protein_g=3, carbs_g=25, fat_g=10, fdc_id=None)
        else:
            # Generic fallback
            return MealItem(name=corrected_name, qty=1, unit="serving", kcal=100, protein_g=5, carbs_g=15, fat_g=3, fdc_id=None)