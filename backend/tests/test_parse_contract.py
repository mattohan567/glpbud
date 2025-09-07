import pytest
from app.schemas import ParseMealTextReq, MealParse, MealItem, MacroTotals

def test_parse_roundtrip():
    """Test that parse request and response schemas work correctly."""
    req = ParseMealTextReq(text="1 cup oatmeal with banana and 1 tbsp PB")
    
    # Simulate parse call output
    out = MealParse(
        items=[
            MealItem(
                name="oatmeal",
                qty=234,
                unit="g",
                kcal=154,
                protein_g=6,
                carbs_g=27,
                fat_g=3,
                fdc_id=169705
            ),
            MealItem(
                name="banana",
                qty=118,
                unit="g",
                kcal=105,
                protein_g=1.3,
                carbs_g=27,
                fat_g=0.4,
                fdc_id=173944
            ),
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
        ],
        totals=MacroTotals(kcal=353, protein_g=11.3, carbs_g=57.5, fat_g=11.4),
        confidence=0.85,
        questions=None,
        low_confidence=False
    )
    
    assert 0 <= out.confidence <= 1
    assert out.totals.kcal == 353
    assert len(out.items) == 3
    assert not out.low_confidence

def test_low_confidence_parse():
    """Test low confidence parse behavior."""
    out = MealParse(
        items=[
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
        ],
        totals=MacroTotals(kcal=400, protein_g=20, carbs_g=50, fat_g=15),
        confidence=0.55,
        questions=["Was this the complete meal?", "Any condiments or sides?"],
        low_confidence=True
    )
    
    assert out.low_confidence
    assert out.questions is not None
    assert len(out.questions) == 2
    assert out.confidence < 0.6

def test_macro_totals_validation():
    """Test that macro totals have proper validation."""
    # Should not allow negative values
    with pytest.raises(ValueError):
        MacroTotals(kcal=-100, protein_g=10, carbs_g=20, fat_g=5)
    
    # Valid totals
    totals = MacroTotals(kcal=500, protein_g=25, carbs_g=60, fat_g=20)
    assert totals.kcal == 500
    assert totals.protein_g == 25

def test_meal_item_units():
    """Test various unit formats for meal items."""
    units = ["g", "ml", "cup", "tbsp", "tsp", "oz", "lb", "piece", "serving"]
    
    for unit in units:
        item = MealItem(
            name="test food",
            qty=100,
            unit=unit,
            kcal=100,
            protein_g=10,
            carbs_g=10,
            fat_g=5
        )
        assert item.unit == unit