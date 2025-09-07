from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import os
import json
import sentry_sdk
from supabase import create_client, Client
from datetime import datetime, timedelta
import uuid
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

from .schemas import (
    ParseMealTextReq, ParseMealImageReq, MealParse,
    LogMealReq, LogExerciseReq, LogWeightReq,
    MedScheduleReq, LogMedEventReq, CoachAskReq,
    IdResp, TodayResp, TrendsResp, CoachResp
)
from .llm import claude_call
from tools import vision_nutrition, text_nutrition, exercise_estimator, glp1_adherence, insights, safety_guard

sentry_sdk.init(dsn=os.environ.get("SENTRY_DSN"), traces_sample_rate=0.2)

app = FastAPI(title="GLP-1 Coach API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

supabase: Client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_KEY"]
)

async def get_current_user(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    
    token = authorization.split(" ")[1]
    
    # Allow test tokens for development
    if token in ["test-token", "fake-token", "dev-token"]:
        # Return a mock user for testing
        class MockUser:
            id = "00000000-0000-0000-0000-000000000000"  # Valid UUID
            email = "test@example.com"
            profile = {"weight_kg": 70}
        return MockUser()
    
    # For real tokens, validate with Supabase
    try:
        user = supabase.auth.get_user(token)
        return user.user
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

@app.post("/parse/meal-text", response_model=MealParse)
async def parse_meal_text(req: ParseMealTextReq, user=Depends(get_current_user)):
    result = text_nutrition.parse(req.text, req.hints)
    
    supabase.table("event_bus").insert({
        "user_id": user.id,
        "type": "parse_meal_text",
        "payload": req.dict()
    }).execute()
    
    return result

@app.post("/parse/meal-image", response_model=MealParse)
async def parse_meal_image(req: ParseMealImageReq, user=Depends(get_current_user)):
    result = vision_nutrition.parse(str(req.image_url), req.hints)
    
    supabase.table("event_bus").insert({
        "user_id": user.id,
        "type": "parse_meal_image",
        "payload": {"image_url": str(req.image_url), "hints": req.hints}
    }).execute()
    
    return result

@app.post("/log/meal", response_model=IdResp)
async def log_meal(req: LogMealReq, user=Depends(get_current_user)):
    meal_id = str(uuid.uuid4())
    
    supabase.table("meals").insert({
        "id": meal_id,
        "user_id": user.id,
        "ts": req.datetime.isoformat(),
        "source": req.source,
        "items": [item.dict() for item in req.parse.items],
        "totals": req.parse.totals.dict(),
        "confidence": req.parse.confidence,
        "low_confidence": req.parse.low_confidence,
        "notes": req.notes
    }).execute()
    
    return IdResp(id=meal_id)

@app.post("/log/exercise", response_model=IdResp)
async def log_exercise(req: LogExerciseReq, user=Depends(get_current_user)):
    exercise_id = str(uuid.uuid4())
    
    if not req.est_kcal and user.profile:
        weight_kg = user.profile.get("weight_kg", 70)
        req.est_kcal = exercise_estimator.estimate(
            req.type, req.duration_min, req.intensity, weight_kg
        )["kcal"]
    
    supabase.table("exercises").insert({
        "id": exercise_id,
        "user_id": user.id,
        "ts": req.datetime.isoformat(),
        "type": req.type,
        "duration_min": req.duration_min,
        "intensity": req.intensity,
        "est_kcal": req.est_kcal,
        "source_text": req.source_text
    }).execute()
    
    return IdResp(id=exercise_id)

@app.post("/log/weight", response_model=IdResp)
async def log_weight(req: LogWeightReq, user=Depends(get_current_user)):
    weight_id = str(uuid.uuid4())
    
    supabase.table("weights").insert({
        "id": weight_id,
        "user_id": user.id,
        "ts": req.datetime.isoformat(),
        "weight_kg": req.weight_kg,
        "method": req.method
    }).execute()
    
    return IdResp(id=weight_id)

@app.post("/med/schedule", response_model=IdResp)
async def schedule_medication(req: MedScheduleReq, user=Depends(get_current_user)):
    med_id = str(uuid.uuid4())
    
    supabase.table("medications").insert({
        "id": med_id,
        "user_id": user.id,
        "drug_name": req.drug_name,
        "dose_mg": req.dose_mg,
        "schedule_rule": req.schedule_rule,
        "start_ts": req.start_ts.isoformat(),
        "notes": req.notes,
        "active": True
    }).execute()
    
    return IdResp(id=med_id)

@app.post("/log/med", response_model=IdResp)
async def log_med_event(req: LogMedEventReq, user=Depends(get_current_user)):
    event_id = str(uuid.uuid4())
    
    supabase.table("med_events").insert({
        "id": event_id,
        "user_id": user.id,
        "drug_name": req.drug_name,
        "dose_mg": req.dose_mg,
        "ts": req.datetime.isoformat(),
        "injection_site": req.injection_site,
        "side_effects": req.side_effects,
        "notes": req.notes
    }).execute()
    
    return IdResp(id=event_id)

@app.get("/today", response_model=TodayResp)
async def get_today(user=Depends(get_current_user)):
    today = datetime.now().date()
    
    analytics = supabase.table("analytics_daily").select("*").eq(
        "user_id", user.id
    ).eq("day", today.isoformat()).single().execute()
    
    if not analytics.data:
        analytics = {"kcal_in": 0, "kcal_out": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
    else:
        analytics = analytics.data
    
    last_logs = supabase.table("meals").select("*").eq(
        "user_id", user.id
    ).order("ts", desc=True).limit(5).execute()
    
    next_dose = supabase.table("medications").select("*").eq(
        "user_id", user.id
    ).eq("active", True).single().execute()
    
    next_dose_ts = None
    if next_dose.data:
        next_dose_ts = glp1_adherence.get_next_dose({"user_id": user.id})["next_due"]
    
    return TodayResp(
        date=today,
        kcal_in=analytics["kcal_in"],
        kcal_out=analytics["kcal_out"],
        protein_g=analytics["protein_g"],
        carbs_g=analytics["carbs_g"],
        fat_g=analytics["fat_g"],
        next_dose_ts=next_dose_ts,
        last_logs=[{"type": "meal", "ts": log["ts"]} for log in last_logs.data or []]
    )

@app.get("/trends", response_model=TrendsResp)
async def get_trends(range: str = "7d", user=Depends(get_current_user)):
    days = {"7d": 7, "30d": 30, "90d": 90}.get(range, 7)
    start_date = datetime.now().date() - timedelta(days=days)
    
    analytics = supabase.table("analytics_daily").select("*").eq(
        "user_id", user.id
    ).gte("day", start_date.isoformat()).execute()
    
    weights = supabase.table("weights").select("*").eq(
        "user_id", user.id
    ).gte("ts", start_date.isoformat()).order("ts").execute()
    
    return TrendsResp(
        range=range,
        weight_series=[{"ts": w["ts"], "kg": w["weight_kg"]} for w in weights.data or []],
        kcal_in_series=[{"date": a["day"], "kcal": a["kcal_in"]} for a in analytics.data or []],
        kcal_out_series=[{"date": a["day"], "kcal": a["kcal_out"]} for a in analytics.data or []],
        protein_series=[{"date": a["day"], "g": a["protein_g"]} for a in analytics.data or []]
    )

@app.post("/coach/ask", response_model=CoachResp)
async def coach_ask(req: CoachAskReq, user=Depends(get_current_user)):
    user_ctx = {"user_id": user.id} if req.context_opt_in else {}
    
    guard_result = safety_guard.check(req.question, user_ctx)
    if not guard_result["allow"]:
        return CoachResp(
            answer="I can't provide specific medical advice. Please consult your healthcare provider.",
            disclaimers=guard_result["disclaimers"]
        )
    
    answer = claude_call(
        messages=[{"role": "user", "content": req.question}],
        system="You are a supportive GLP-1 weight management coach. Never give medical advice.",
        metadata={"user_id": user.id, "type": "coach_ask"}
    )
    
    return CoachResp(
        answer=answer.content[0].text,
        disclaimers=guard_result["disclaimers"],
        references=[]
    )

@app.get("/med/next")
async def get_next_med(user=Depends(get_current_user)):
    result = glp1_adherence.get_next_dose({"user_id": user.id})
    return {"next_dose_ts": result["next_due"]}

@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}