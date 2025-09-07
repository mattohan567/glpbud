import os
import sys
from datetime import datetime, timedelta
from supabase import create_client
import uuid

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.schemas import MealItem, MacroTotals

# Initialize Supabase client
supabase = create_client(
    os.environ.get("SUPABASE_URL", "https://example.supabase.co"),
    os.environ.get("SUPABASE_KEY", "your-key-here")
)

def seed_database():
    """Seed the database with demo data."""
    
    # Create demo user
    user_id = str(uuid.uuid4())
    user_data = {
        "id": user_id,
        "email": "demo@glp1coach.com",
        "height_cm": 175,
        "sex": "male",
        "activity_level": "moderate",
        "timezone": "America/Los_Angeles"
    }
    
    print("Creating demo user...")
    supabase.table("users").upsert(user_data).execute()
    
    # Create GLP-1 medication schedule
    print("Creating medication schedule...")
    medication_data = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "drug_name": "semaglutide",
        "dose_mg": 0.5,
        "schedule_rule": "FREQ=WEEKLY;BYDAY=SU",
        "start_ts": datetime.now().isoformat(),
        "notes": "Ozempic for weight management",
        "active": True
    }
    supabase.table("medications").insert(medication_data).execute()
    
    # Create sample meals
    print("Creating sample meals...")
    meals = [
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "ts": (datetime.now() - timedelta(days=1, hours=8)).isoformat(),
            "source": "text",
            "text_raw": "2 eggs scrambled with spinach, 2 slices whole wheat toast",
            "items": [
                {
                    "name": "scrambled eggs",
                    "qty": 100,
                    "unit": "g",
                    "kcal": 155,
                    "protein_g": 11,
                    "carbs_g": 1.1,
                    "fat_g": 11,
                    "fdc_id": 172183
                },
                {
                    "name": "whole wheat toast",
                    "qty": 56,
                    "unit": "g",
                    "kcal": 138,
                    "protein_g": 5.4,
                    "carbs_g": 23.6,
                    "fat_g": 2.4,
                    "fdc_id": 174897
                }
            ],
            "totals": {
                "kcal": 293,
                "protein_g": 16.4,
                "carbs_g": 24.7,
                "fat_g": 13.4
            },
            "confidence": 0.92,
            "low_confidence": False,
            "notes": "Breakfast"
        },
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "ts": (datetime.now() - timedelta(hours=4)).isoformat(),
            "source": "image",
            "image_url": "https://example.com/lunch.jpg",
            "items": [
                {
                    "name": "grilled chicken salad",
                    "qty": 350,
                    "unit": "g",
                    "kcal": 320,
                    "protein_g": 35,
                    "carbs_g": 12,
                    "fat_g": 14,
                    "fdc_id": None
                },
                {
                    "name": "balsamic vinaigrette",
                    "qty": 30,
                    "unit": "ml",
                    "kcal": 90,
                    "protein_g": 0,
                    "carbs_g": 6,
                    "fat_g": 8,
                    "fdc_id": 173590
                }
            ],
            "totals": {
                "kcal": 410,
                "protein_g": 35,
                "carbs_g": 18,
                "fat_g": 22
            },
            "confidence": 0.88,
            "low_confidence": False,
            "notes": "Lunch at work"
        }
    ]
    
    for meal in meals:
        supabase.table("meals").insert(meal).execute()
    
    # Create sample exercise
    print("Creating sample exercise...")
    exercise_data = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "ts": (datetime.now() - timedelta(hours=2)).isoformat(),
        "type": "walking",
        "duration_min": 45,
        "intensity": "moderate",
        "est_kcal": 180,
        "source_text": "Evening walk in the park"
    }
    supabase.table("exercises").insert(exercise_data).execute()
    
    # Create weight entries
    print("Creating weight history...")
    weights = [
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "ts": (datetime.now() - timedelta(days=7)).isoformat(),
            "weight_kg": 85.5,
            "method": "scale"
        },
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "ts": datetime.now().isoformat(),
            "weight_kg": 84.8,
            "method": "scale"
        }
    ]
    
    for weight in weights:
        supabase.table("weights").insert(weight).execute()
    
    # Seed tips content
    tips = [
        "Hydrate: Target ~30-35 ml/kg/day; sip throughout the day",
        "Protein anchor each meal (≥25-35g) for satiety & lean mass",
        "Fiber (vegetables, beans, berries) to ease constipation risk",
        "Small portions, eat slowly; GLP-1 slows gastric emptying",
        "Gentle movement after meals (10-15 min walk) helps glucose",
        "Resistance training 2-4×/week to preserve muscle",
        "Prioritize sleep (7-9h); poor sleep increases hunger hormones",
        "If nausea: small bland snacks, ginger tea, avoid high-fat",
        "Rotate injection sites to reduce local irritation",
        "Weigh 1-2×/week, same conditions; focus on trend",
        "Don't chase extreme deficits; sustainable beats crash",
        "Always consult your clinician before dose changes"
    ]
    
    print(f"\nSeeded tips: {len(tips)} items")
    
    # Create sample tool runs for observability
    print("Creating sample tool runs...")
    tool_runs = [
        {
            "user_id": user_id,
            "tool_name": "text_nutrition",
            "input": {"text": "2 eggs scrambled with spinach"},
            "output": {"success": True, "confidence": 0.92},
            "model": "claude-3-5-haiku-20241022",
            "latency_ms": 450,
            "cost_usd": 0.0005,
            "success": True
        },
        {
            "user_id": user_id,
            "tool_name": "vision_nutrition",
            "input": {"image_url": "https://example.com/lunch.jpg"},
            "output": {"success": True, "confidence": 0.88},
            "model": "claude-3-5-sonnet-20241022",
            "latency_ms": 1200,
            "cost_usd": 0.001,
            "success": True
        }
    ]
    
    for run in tool_runs:
        supabase.table("tool_runs").insert(run).execute()
    
    print("\n✅ Database seeded successfully!")
    print(f"Demo user: demo@glp1coach.com (ID: {user_id})")
    print("- 2 meals logged")
    print("- 1 exercise logged")
    print("- 2 weight entries")
    print("- 1 GLP-1 medication schedule")
    print("- 2 tool run traces")
    
    return user_id

if __name__ == "__main__":
    seed_database()