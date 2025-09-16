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
        
        Estimate portion sizes from visual cues (plate size, utensils, etc).
        Be accurate with nutritional values based on typical preparations.
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
        
        Use standard portion sizes if not specified. Be accurate with nutritional values.
        Examples:
        - "chicken breast" -> 100g serving
        - "apple" -> 1 medium (182g)
        - "2 eggs" -> 2 large eggs (100g total)
        """
        
        user_message = f"Parse this meal: {text}"
        if hints:
            user_message += f"\nAdditional context: {hints}"
        
        try:
            # Call Claude API
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-haiku-20241022",
                metadata={"tool": "text_nutrition_parse", "text": text[:100]}
            )
            
            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"
            
            # Try to parse JSON
            try:
                # Clean up response - remove any markdown formatting
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
                            fdc_id=None  # Would need USDA API integration for this
                        )
                    )
                
                confidence = float(data.get("confidence", 0.7))
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                # Fallback if parsing fails
                print(f"Failed to parse Claude response: {e}")
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
        multipliers = {'general': 1.0}
        
        # Size indicators
        if any(word in text for word in ['large', 'big', 'huge', 'jumbo', 'xl']):
            multipliers['general'] = 1.4
        elif any(word in text for word in ['small', 'little', 'mini', 'tiny', 'xs']):
            multipliers['general'] = 0.7
        elif any(word in text for word in ['medium', 'regular', 'normal']):
            multipliers['general'] = 1.0
        
        # Quantity indicators
        if '2 ' in text or 'two ' in text or 'double' in text:
            multipliers['general'] = 2.0
        elif '3 ' in text or 'three ' in text or 'triple' in text:
            multipliers['general'] = 3.0
        elif 'half' in text or '0.5' in text:
            multipliers['general'] = 0.5
            
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

vision_nutrition = VisionNutrition()
text_nutrition = TextNutrition()