import json
from typing import Optional, List, Dict, Any
try:
    from app.schemas import MealParse, MealItem, MacroTotals
except ImportError:
    from backend.app.schemas import MealParse, MealItem, MacroTotals

class VisionNutrition:
    def parse(self, image_url: str, hints: Optional[str] = None) -> MealParse:
        """
        Parse meal photo into items/macros with confidence.
        TODO: Integrate Claude Vision API for actual parsing
        """
        # Dummy implementation - replace with Claude Vision call
        items = [
            MealItem(
                name="grilled chicken breast",
                qty=150,
                unit="g",
                kcal=248,
                protein_g=46.5,
                carbs_g=0,
                fat_g=5.4,
                fdc_id=171077
            ),
            MealItem(
                name="brown rice",
                qty=158,
                unit="g",
                kcal=175,
                protein_g=3.7,
                carbs_g=36.5,
                fat_g=1.4,
                fdc_id=169704
            ),
            MealItem(
                name="steamed broccoli",
                qty=91,
                unit="g",
                kcal=31,
                protein_g=2.6,
                carbs_g=6.0,
                fat_g=0.3,
                fdc_id=170379
            )
        ]
        
        totals = MacroTotals(
            kcal=sum(item.kcal for item in items),
            protein_g=sum(item.protein_g for item in items),
            carbs_g=sum(item.carbs_g for item in items),
            fat_g=sum(item.fat_g for item in items)
        )
        
        return MealParse(
            items=items,
            totals=totals,
            confidence=0.85,
            questions=None,
            low_confidence=False
        )

class TextNutrition:
    def parse(self, text: str, hints: Optional[str] = None) -> MealParse:
        """
        Parse text meal into items/macros with USDA mapping.
        TODO: Integrate Claude text parsing with USDA database lookup
        """
        # Dummy implementation - replace with Claude + USDA API
        if "oatmeal" in text.lower():
            items = [
                MealItem(
                    name="oatmeal",
                    qty=234,
                    unit="g",
                    kcal=154,
                    protein_g=6,
                    carbs_g=27,
                    fat_g=3,
                    fdc_id=169705
                )
            ]
            
            if "banana" in text.lower():
                items.append(
                    MealItem(
                        name="banana",
                        qty=118,
                        unit="g",
                        kcal=105,
                        protein_g=1.3,
                        carbs_g=27,
                        fat_g=0.4,
                        fdc_id=173944
                    )
                )
            
            if "peanut butter" in text.lower() or "pb" in text.lower():
                items.append(
                    MealItem(
                        name="peanut butter",
                        qty=16,
                        unit="g",
                        kcal=94,
                        protein_g=4,
                        carbs_g=3.5,
                        fat_g=8,
                        fdc_id=172470
                    )
                )
        else:
            # Default fallback
            items = [
                MealItem(
                    name="mixed meal",
                    qty=300,
                    unit="g",
                    kcal=400,
                    protein_g=20,
                    carbs_g=50,
                    fat_g=15,
                    fdc_id=None
                )
            ]
        
        totals = MacroTotals(
            kcal=sum(item.kcal for item in items),
            protein_g=sum(item.protein_g for item in items),
            carbs_g=sum(item.carbs_g for item in items),
            fat_g=sum(item.fat_g for item in items)
        )
        
        confidence = 0.9 if len(items) > 1 else 0.6
        
        return MealParse(
            items=items,
            totals=totals,
            confidence=confidence,
            questions=["Was this the complete meal?"] if confidence < 0.7 else None,
            low_confidence=confidence < 0.6
        )

vision_nutrition = VisionNutrition()
text_nutrition = TextNutrition()