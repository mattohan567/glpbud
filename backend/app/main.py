from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import os
import json
import sentry_sdk
from supabase import create_client, Client
from datetime import datetime, timedelta
import uuid
from dotenv import load_dotenv
import pathlib
import logging
import time

# Import our logging configuration
from .logging_config import (
    setup_logging, log_error, log_api_call, 
    AppError, ValidationError, AuthenticationError, 
    AuthorizationError, ExternalServiceError, DatabaseError
)

# Import validation utilities
from .validation import (
    sanitize_text, validate_weight, validate_exercise_duration,
    validate_meal_items, validate_confidence, validate_intensity,
    validate_image_url, sanitize_coach_message, validate_drug_name,
    validate_medication_dose
)

# Import health checking
from .health import health_checker, metrics_collector

# Import rate limiting
from .rate_limiter import check_rate_limit

# Load environment variables from .env file
# Try to load from parent directory (where .env actually is)
env_path = pathlib.Path(__file__).parent.parent.parent / '.env'
load_dotenv(dotenv_path=env_path)

from .schemas import (
    ParseMealTextReq, ParseMealImageReq, MealParse,
    LogMealReq, LogExerciseReq, LogWeightReq,
    MedScheduleReq, LogMedEventReq, CoachAskReq,
    IdResp, TodayResp, TrendsResp, CoachResp,
    CoachChatReq, AgenticCoachResp, LoggedAction,
    HistoryResp, HistoryEntryResp, UpdateMealReq, UpdateExerciseReq, UpdateWeightReq
)
from .llm import claude_call
try:
    # Try local development import first
    from tools import vision_nutrition, text_nutrition, exercise_estimator, glp1_adherence, insights, safety_guard
except ImportError:
    # Production Docker import
    from backend.tools import vision_nutrition, text_nutrition, exercise_estimator, glp1_adherence, insights, safety_guard

# Initialize logging
logger = setup_logging()

sentry_sdk.init(dsn=os.environ.get("SENTRY_DSN"), traces_sample_rate=0.2)

app = FastAPI(title="GLP-1 Coach API", version="1.0.0")

# Add request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Generate request ID for tracing
    request_id = str(uuid.uuid4())
    
    # Log request start
    logger.info(
        f"Request started: {request.method} {request.url.path}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "query_params": str(request.query_params),
            "client_ip": request.client.host if request.client else None
        }
    )
    
    # Process request
    try:
        response = await call_next(request)
        
        # Calculate execution time
        execution_time = (time.time() - start_time) * 1000
        
        # Update metrics
        metrics_collector.increment_requests()
        if response.status_code >= 400:
            metrics_collector.increment_errors()
        
        # Log successful completion
        log_api_call(
            logger=logger,
            endpoint=f"{request.method} {request.url.path}",
            execution_time=execution_time,
            status_code=response.status_code
        )
        
        return response
        
    except Exception as e:
        execution_time = (time.time() - start_time) * 1000
        
        # Log error
        log_error(logger, e, {
            "request_id": request_id,
            "endpoint": f"{request.method} {request.url.path}",
            "execution_time": execution_time
        })
        
        # Re-raise the exception
        raise

# CORS Configuration - Restrict to known domains
ALLOWED_ORIGINS = [
    "http://localhost:3000",  # Local development frontend
    "http://localhost:8080",  # iOS simulator
    "https://glp1coach-api.fly.dev",  # Production API
    "https://app.glp1coach.com",  # Production frontend (if you have one)
]

# Add development origins if in development mode
if os.environ.get("ENVIRONMENT") == "development":
    ALLOWED_ORIGINS.extend([
        "http://localhost:*",  # Any localhost port for development
        "http://127.0.0.1:*",
    ])

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

supabase: Client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_KEY"]
)

def clean_name(name: str) -> str:
    """Clean and standardize food/exercise names for display and storage"""
    if not name:
        return name
    
    # Remove common suffixes and prefixes that aren't user-friendly
    name = name.strip()
    
    # Remove size indicators from display name if they're redundant
    # Keep them if they're meaningful (like "large pizza" vs "pizza (large)")
    if name.endswith(" (large)") or name.endswith(" (small)"):
        # Keep meaningful size descriptors
        return name
    
    # Clean up obvious parsing artifacts
    replacements = {
        "meal (from photo)": "photo meal",
        "unidentified food from photo": "unknown food",
        "unrecognized food": "unknown food",
    }
    
    for old, new in replacements.items():
        if name == old:
            return new
    
    # Capitalize first letter of each word for display
    return name.title()

async def get_current_user(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    
    token = authorization.split(" ")[1]
    
    # Allow test tokens ONLY in development environment
    is_development = os.environ.get("ENVIRONMENT") == "development"
    if is_development and token in ["test-token", "fake-token", "dev-token"]:
        # Return a mock user for testing - DEVELOPMENT ONLY
        class MockUser:
            id = "00000000-0000-0000-0000-000000000000"  # Valid UUID
            email = "test@example.com"
            profile = {"weight_kg": 70}
        
        user = MockUser()
        
        # Ensure test user exists in our users table - use upsert approach directly
        print(f"🔍 Ensuring test user record exists for {user.email} ({user.id})")
        try:
            # First try direct upsert which handles both insert and update
            supabase.table("users").upsert({
                "id": user.id,
                "email": user.email,
                "created_at": datetime.now().isoformat()
            }, on_conflict="id").execute()
            print(f"✅ Test user record ensured via upsert")
        except Exception as upsert_error:
            print(f"⚠️  Test user upsert failed: {upsert_error}")
            # Don't delete user data - just log and continue
            print(f"✅ Continuing with existing test user - no data will be deleted")
        
        return user
    
    # For real tokens, validate with Supabase
    try:
        user_response = supabase.auth.get_user(token)
        user = user_response.user
        
        # Ensure user exists in our users table - use upsert approach directly
        print(f"🔍 Ensuring user record exists for {user.email} ({user.id})")
        try:
            # First try direct upsert which handles both insert and update
            supabase.table("users").upsert({
                "id": user.id,
                "email": user.email,
                "created_at": datetime.now().isoformat()
            }, on_conflict="id").execute()
            print(f"✅ User record ensured via upsert")
        except Exception as upsert_error:
            print(f"⚠️  Upsert failed: {upsert_error}")
            # If upsert fails due to email conflict, clean up and try again
            try:
                print(f"🧹 Cleaning up conflicting user records for {user.email}")
                # Delete any user with this email
                supabase.table("users").delete().eq("email", user.email).execute()
                # Now insert the correct record
                supabase.table("users").insert({
                    "id": user.id,
                    "email": user.email,
                    "created_at": datetime.now().isoformat()
                }).execute()
                print(f"✅ User record created after cleanup")
            except Exception as cleanup_error:
                print(f"❌ Cleanup failed: {cleanup_error}")
                # Last resort - ignore the error and continue
                pass
            # Continue anyway - user validation succeeded, just database issue
            
        return user
    except Exception as e:
        print(f"❌ Authentication error: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")

async def verify_user_owns_resource(user_id: str, resource_table: str, resource_id: str) -> bool:
    """Verify that a user owns a specific resource"""
    try:
        result = supabase.table(resource_table).select("user_id").eq("id", resource_id).single().execute()
        if not result.data:
            return False
        return result.data["user_id"] == user_id
    except Exception:
        return False

@app.post("/parse/meal-text", response_model=MealParse)
async def parse_meal_text(req: ParseMealTextReq, request: Request, user=Depends(get_current_user)):
    # Apply rate limiting for expensive parse operations
    check_rate_limit(request, user.id, 'parse')
    
    try:
        # Validate and sanitize input
        clean_text = sanitize_text(req.text)
        clean_hints = sanitize_text(req.hints) if req.hints else None
        
        if len(clean_text.strip()) == 0:
            raise ValidationError("Meal text cannot be empty", "text")
        
        logger.info(
            f"Parsing meal text for user {user.id}",
            extra={
                "user_id": user.id,
                "text_length": len(clean_text),
                "has_hints": bool(clean_hints)
            }
        )
        
        # Parse the meal
        result = text_nutrition.parse(clean_text, clean_hints)
        
        # Log event for analytics
        supabase.table("event_bus").insert({
            "user_id": user.id,
            "type": "parse_meal_text",
            "payload": {
                "text_length": len(clean_text),
                "confidence": result.confidence,
                "items_found": len(result.items)
            }
        }).execute()
        
        return result
        
    except ValidationError as e:
        logger.warning(f"Meal text validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except Exception as e:
        log_error(logger, e, {"user_id": user.id, "text_preview": req.text[:100]})
        raise HTTPException(status_code=500, detail="Failed to parse meal text")

@app.post("/parse/meal-image", response_model=MealParse)
async def parse_meal_image(req: ParseMealImageReq, request: Request, user=Depends(get_current_user)):
    # Apply rate limiting for expensive parse operations
    check_rate_limit(request, user.id, 'parse')
    
    try:
        # Validate and sanitize input
        clean_image_url = validate_image_url(req.image_url)
        clean_hints = sanitize_text(req.hints) if req.hints else None
        
        logger.info(
            f"Parsing meal image for user {user.id}",
            extra={
                "user_id": user.id,
                "is_data_url": clean_image_url.startswith("data:"),
                "has_hints": bool(clean_hints)
            }
        )
        
        # Parse the meal image
        result = vision_nutrition.parse(clean_image_url, clean_hints)
        
        # Log event for analytics (don't log full image URL for privacy)
        supabase.table("event_bus").insert({
            "user_id": user.id,
            "type": "parse_meal_image",
            "payload": {
                "is_data_url": clean_image_url.startswith("data:"),
                "confidence": result.confidence,
                "items_found": len(result.items)
            }
        }).execute()
        
        return result
        
    except ValidationError as e:
        logger.warning(f"Meal image validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except Exception as e:
        log_error(logger, e, {"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to parse meal image")

@app.post("/log/meal", response_model=IdResp)
async def log_meal(req: LogMealReq, user=Depends(get_current_user)):
    meal_id = str(uuid.uuid4())
    
    try:
        # Validate and sanitize input
        validated_items = validate_meal_items([item.dict() for item in req.parse.items])
        validated_confidence = validate_confidence(req.parse.confidence)
        clean_notes = sanitize_text(req.notes) if req.notes else None
        
        logger.info(
            f"Logging meal for user {user.id}",
            extra={
                "user_id": user.id,
                "meal_id": meal_id,
                "items_count": len(req.parse.items),
                "source": req.source,
                "confidence": req.parse.confidence
            }
        )
        
        # Items are already validated and cleaned
        
        # Insert into database
        result = supabase.table("meals").insert({
            "id": meal_id,
            "user_id": user.id,
            "ts": req.datetime.isoformat(),
            "source": req.source,
            "items": validated_items,
            "totals": req.parse.totals.dict(),
            "confidence": validated_confidence,
            "low_confidence": req.parse.low_confidence,
            "notes": clean_notes
        }).execute()
        
        if not result.data:
            raise DatabaseError("insert", "Failed to insert meal record")
        
        logger.info(
            f"Meal logged successfully",
            extra={
                "user_id": user.id,
                "meal_id": meal_id,
                "total_kcal": req.parse.totals.kcal
            }
        )
        
        return IdResp(id=meal_id)
        
    except ValidationError as e:
        logger.warning(f"Meal validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except DatabaseError as e:
        log_error(logger, e, {"user_id": user.id, "meal_id": meal_id})
        raise HTTPException(status_code=500, detail="Failed to save meal. Please try again.")
    except Exception as e:
        log_error(logger, e, {"user_id": user.id, "meal_id": meal_id})
        raise HTTPException(status_code=500, detail="An unexpected error occurred")

@app.post("/log/exercise", response_model=IdResp)
async def log_exercise(req: LogExerciseReq, user=Depends(get_current_user)):
    exercise_id = str(uuid.uuid4())
    
    try:
        # Validate and sanitize input
        clean_type = sanitize_text(req.type, 100)
        validated_duration = validate_exercise_duration(req.duration_min)
        clean_intensity = validate_intensity(req.intensity) if req.intensity else "moderate"
        clean_source_text = sanitize_text(req.source_text) if req.source_text else None
        
        logger.info(
            f"Logging exercise for user {user.id}",
            extra={
                "user_id": user.id,
                "exercise_id": exercise_id,
                "type": clean_type,
                "duration_min": validated_duration,
                "intensity": clean_intensity
            }
        )
        
        # Estimate calories if not provided
        est_kcal = req.est_kcal
        if not est_kcal and hasattr(user, 'profile') and user.profile:
            weight_kg = user.profile.get("weight_kg", 70)
            try:
                estimation = exercise_estimator.estimate(
                    clean_type, validated_duration, clean_intensity, weight_kg
                )
                est_kcal = estimation["kcal"]
            except Exception as e:
                logger.warning(f"Exercise calorie estimation failed: {e}", extra={"user_id": user.id})
                est_kcal = 0  # Default to 0 if estimation fails
        
        # Insert into database
        result = supabase.table("exercises").insert({
            "id": exercise_id,
            "user_id": user.id,
            "ts": req.datetime.isoformat(),
            "type": clean_type,
            "duration_min": validated_duration,
            "intensity": clean_intensity,
            "est_kcal": est_kcal or 0,
            "source_text": clean_source_text
        }).execute()
        
        if not result.data:
            raise DatabaseError("insert", "Failed to insert exercise record")
        
        logger.info(
            f"Exercise logged successfully",
            extra={
                "user_id": user.id,
                "exercise_id": exercise_id,
                "est_kcal": est_kcal
            }
        )
        
        return IdResp(id=exercise_id)
        
    except ValidationError as e:
        logger.warning(f"Exercise validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except DatabaseError as e:
        log_error(logger, e, {"user_id": user.id, "exercise_id": exercise_id})
        raise HTTPException(status_code=500, detail="Failed to save exercise. Please try again.")
    except Exception as e:
        log_error(logger, e, {"user_id": user.id, "exercise_id": exercise_id})
        raise HTTPException(status_code=500, detail="An unexpected error occurred")

@app.post("/log/weight", response_model=IdResp)
async def log_weight(req: LogWeightReq, user=Depends(get_current_user)):
    weight_id = str(uuid.uuid4())
    
    try:
        # Validate and sanitize input
        validated_weight = validate_weight(req.weight_kg)
        clean_method = sanitize_text(req.method, 50) if req.method else "manual"
        
        logger.info(
            f"Logging weight for user {user.id}",
            extra={
                "user_id": user.id,
                "weight_id": weight_id,
                "weight_kg": validated_weight,
                "method": clean_method
            }
        )
        
        # Insert into database
        result = supabase.table("weights").insert({
            "id": weight_id,
            "user_id": user.id,
            "ts": req.datetime.isoformat(),
            "weight_kg": validated_weight,
            "method": clean_method
        }).execute()
        
        if not result.data:
            raise DatabaseError("insert", "Failed to insert weight record")
        
        logger.info(
            f"Weight logged successfully",
            extra={
                "user_id": user.id,
                "weight_id": weight_id,
                "weight_kg": validated_weight
            }
        )
        
        return IdResp(id=weight_id)
        
    except ValidationError as e:
        logger.warning(f"Weight validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except DatabaseError as e:
        log_error(logger, e, {"user_id": user.id, "weight_id": weight_id})
        raise HTTPException(status_code=500, detail="Failed to save weight. Please try again.")
    except Exception as e:
        log_error(logger, e, {"user_id": user.id, "weight_id": weight_id})
        raise HTTPException(status_code=500, detail="An unexpected error occurred")

@app.post("/med/schedule", response_model=IdResp)
async def schedule_medication(req: MedScheduleReq, user=Depends(get_current_user)):
    med_id = str(uuid.uuid4())
    
    try:
        # Validate and sanitize input
        clean_drug_name = validate_drug_name(req.drug_name)
        validated_dose = validate_medication_dose(req.dose_mg)
        clean_schedule = sanitize_text(req.schedule_rule, 200)
        clean_notes = sanitize_text(req.notes) if req.notes else None
        
        logger.info(
            f"Scheduling medication for user {user.id}",
            extra={
                "user_id": user.id,
                "medication_id": med_id,
                "drug_name": clean_drug_name,
                "dose_mg": validated_dose
            }
        )
        
        # Insert into database
        result = supabase.table("medications").insert({
            "id": med_id,
            "user_id": user.id,
            "drug_name": clean_drug_name,
            "dose_mg": validated_dose,
            "schedule_rule": clean_schedule,
            "start_ts": req.start_ts.isoformat(),
            "notes": clean_notes,
            "active": True
        }).execute()
        
        if not result.data:
            raise DatabaseError("insert", "Failed to insert medication schedule")
        
        logger.info(
            f"Medication scheduled successfully",
            extra={
                "user_id": user.id,
                "medication_id": med_id,
                "drug_name": clean_drug_name
            }
        )
        
        return IdResp(id=med_id)
        
    except ValidationError as e:
        logger.warning(f"Medication validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except DatabaseError as e:
        log_error(logger, e, {"user_id": user.id, "medication_id": med_id})
        raise HTTPException(status_code=500, detail="Failed to save medication schedule. Please try again.")
    except Exception as e:
        log_error(logger, e, {"user_id": user.id, "medication_id": med_id})
        raise HTTPException(status_code=500, detail="An unexpected error occurred")

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
    today_start = today.isoformat() + "T00:00:00"
    today_end = today.isoformat() + "T23:59:59"
    
    # Calculate totals directly from meals and exercises for today
    try:
        # Get today's meals
        meals_result = supabase.table("meals").select("*").eq(
            "user_id", user.id
        ).gte("ts", today_start).lte("ts", today_end).execute()
        
        # Calculate meal totals (accessing nested totals JSON)
        kcal_in = sum(meal.get("totals", {}).get("kcal", 0) for meal in meals_result.data or [])
        protein_g = sum(meal.get("totals", {}).get("protein_g", 0) for meal in meals_result.data or [])
        carbs_g = sum(meal.get("totals", {}).get("carbs_g", 0) for meal in meals_result.data or [])
        fat_g = sum(meal.get("totals", {}).get("fat_g", 0) for meal in meals_result.data or [])
        
        # Get today's exercises  
        exercises_result = supabase.table("exercises").select("*").eq(
            "user_id", user.id
        ).gte("ts", today_start).lte("ts", today_end).execute()
        
        # Calculate exercise totals
        kcal_out = sum(ex.get("est_kcal", 0) for ex in exercises_result.data or [])
        
        analytics = {
            "kcal_in": kcal_in,
            "kcal_out": kcal_out, 
            "protein_g": protein_g,
            "carbs_g": carbs_g,
            "fat_g": fat_g
        }
        
    except Exception as e:
        print(f"⚠️  Today calculation failed: {e}")
        analytics = {"kcal_in": 0, "kcal_out": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
    
    last_logs = supabase.table("meals").select("*").eq(
        "user_id", user.id
    ).order("ts", desc=True).limit(5).execute()
    
    # Handle medication next dose - many users don't have medications
    next_dose_ts = None
    try:
        next_dose = supabase.table("medications").select("*").eq(
            "user_id", user.id
        ).eq("active", True).execute()
        
        if next_dose.data:
            next_dose_ts = glp1_adherence.get_next_dose({"user_id": user.id})["next_due"]
    except Exception as e:
        print(f"⚠️  Medication query failed (user may have no medications): {e}")
        next_dose_ts = None
    
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
async def coach_ask(req: CoachAskReq, request: Request, user=Depends(get_current_user)):
    # Apply rate limiting for coach interactions
    check_rate_limit(request, user.id, 'coach')
    
    try:
        # Validate and sanitize input
        clean_question = sanitize_coach_message(req.question)
        user_ctx = {"user_id": user.id} if req.context_opt_in else {}
        
        logger.info(
            f"Coach question from user {user.id}",
            extra={
                "user_id": user.id,
                "question_length": len(clean_question),
                "context_opt_in": req.context_opt_in
            }
        )
        
        # Safety check
        guard_result = safety_guard.check(clean_question, user_ctx)
        if not guard_result["allow"]:
            logger.info(f"Coach question blocked by safety guard", extra={"user_id": user.id})
            return CoachResp(
                answer="I can't provide specific medical advice. Please consult your healthcare provider.",
                disclaimers=guard_result["disclaimers"]
            )
        
        # Build context for more personalized coaching
        context = ""
        if req.context_opt_in and user_ctx:
            # Get recent user data for context
            today = datetime.now().date()
            week_ago = today - timedelta(days=7)
            
            # Get recent meals
            recent_meals = supabase.table("meals").select("*").eq(
                "user_id", user.id
            ).gte("ts", week_ago.isoformat()).limit(10).execute()
            
            # Get recent weights
            recent_weights = supabase.table("weights").select("*").eq(
                "user_id", user.id
            ).gte("ts", week_ago.isoformat()).order("ts", desc=True).limit(3).execute()
            
            if recent_meals.data or recent_weights.data:
                context = "\n\nUser context (last 7 days):\n"
                if recent_weights.data:
                    context += f"- Latest weight: {recent_weights.data[0]['weight_kg']}kg\n"
                if recent_meals.data:
                    total_kcal = sum(m.get('kcal', 0) for m in recent_meals.data)
                    avg_daily = total_kcal / 7
                    context += f"- Average daily calories: {int(avg_daily)} kcal\n"
        
        system_prompt = """You are a supportive GLP-1 weight management coach. 
    Key principles:
    1. Be encouraging and non-judgmental
    2. Provide evidence-based nutrition and exercise advice
    3. Never provide specific medical advice or medication dosing
    4. Focus on sustainable lifestyle changes
    5. Acknowledge the challenges of weight management
    6. Celebrate small victories
    
    For GLP-1 medication questions:
    - Provide general education only
    - Always defer medical specifics to healthcare providers
    - Focus on lifestyle factors that support medication effectiveness
    """
        
        answer = claude_call(
            messages=[{"role": "user", "content": req.question + context}],
            system=system_prompt,
            model="claude-3-5-haiku-20241022",
            metadata={"user_id": user.id, "type": "coach_ask"}
        )
        
        # Extract answer text
        answer_text = answer.content[0].text if answer.content else "I'm here to help with your weight management journey. Could you rephrase your question?"
        
        return CoachResp(
            answer=answer_text,
            disclaimers=guard_result["disclaimers"],
            references=[]
        )
        
    except Exception as e:
        logger.error(f"Coach error: {e}", extra={"user_id": user.id})
        raise HTTPException(status_code=500, detail="Coach service temporarily unavailable")

# Agentic Coach with Function Calling
COACH_TOOLS = [
    {
        "name": "log_meal",
        "description": "Parse and log a meal from natural language description. Use this when the user mentions eating something.",
        "input_schema": {
            "type": "object",
            "properties": {
                "meal_description": {
                    "type": "string",
                    "description": "Natural language description of the meal (e.g., 'chicken breast with rice')"
                },
                "time_mentioned": {
                    "type": "string",
                    "description": "Any time reference mentioned (e.g., 'for lunch', 'this morning', 'at 2pm')",
                    "default": None
                }
            },
            "required": ["meal_description"]
        }
    },
    {
        "name": "log_exercise",
        "description": "Log exercise activity from user description. Use this when user mentions physical activity.",
        "input_schema": {
            "type": "object", 
            "properties": {
                "activity_type": {
                    "type": "string",
                    "description": "Type of exercise (e.g., 'running', 'cycling', 'weightlifting')"
                },
                "duration_minutes": {
                    "type": "number",
                    "description": "Duration in minutes"
                },
                "intensity": {
                    "type": "string",
                    "description": "Intensity level: 'low', 'moderate', or 'high'",
                    "enum": ["low", "moderate", "high"],
                    "default": "moderate"
                },
                "time_mentioned": {
                    "type": "string",
                    "description": "Any time reference mentioned (e.g., 'this morning', 'at 6pm', 'after work')",
                    "default": None
                }
            },
            "required": ["activity_type", "duration_minutes"]
        }
    },
    {
        "name": "log_weight",
        "description": "Record weight measurement when user mentions their weight.",
        "input_schema": {
            "type": "object",
            "properties": {
                "weight_kg": {
                    "type": "number",
                    "description": "Weight in kilograms"
                },
                "measurement_time": {
                    "type": "string", 
                    "description": "When the measurement was taken (e.g., 'this morning', 'today')",
                    "default": "now"
                }
            },
            "required": ["weight_kg"]
        }
    }
]

@app.post("/coach/chat", response_model=AgenticCoachResp)
async def agentic_coach_chat(req: CoachChatReq, user=Depends(get_current_user)):
    user_ctx = {"user_id": user.id} if req.context_opt_in else {}
    
    # Safety guard
    guard_result = safety_guard.check(req.message, user_ctx)
    if not guard_result["allow"]:
        return AgenticCoachResp(
            message=guard_result["message"],
            disclaimers=guard_result["disclaimers"]
        )
    
    # Build context for personalized coaching
    context = ""
    if req.context_opt_in:
        today = datetime.now().date()
        week_ago = today - timedelta(days=7)
        
        # Get recent meals
        recent_meals = supabase.table("meals").select("*").eq(
            "user_id", user.id
        ).gte("ts", week_ago.isoformat()).limit(5).execute()
        
        # Get recent weights
        recent_weights = supabase.table("weights").select("*").eq(
            "user_id", user.id
        ).gte("ts", week_ago.isoformat()).order("ts", desc=True).limit(2).execute()
        
        if recent_meals.data or recent_weights.data:
            context = "\n\nUser context (last 7 days):\n"
            if recent_weights.data:
                context += f"- Latest weight: {recent_weights.data[0]['weight_kg']}kg\n"
            if recent_meals.data:
                total_kcal = sum(meal.get("totals", {}).get("kcal", 0) for meal in recent_meals.data)
                avg_daily = total_kcal / 7
                context += f"- Average daily calories: {int(avg_daily)} kcal\n"
    
    system_prompt = f"""You are an agentic GLP-1 weight management coach with the ability to help users by automatically logging their meals, exercises, and weight measurements.

Key principles:
1. Be encouraging and supportive
2. Parse user messages for actionable data (meals, exercises, weight)
3. USE YOUR TOOLS IMMEDIATELY when users mention eating, exercising, or weight measurements
4. Log data proactively - users want convenience and automation
5. Provide helpful coaching advice alongside data logging
6. Never provide specific medical advice

Available tools: {', '.join([tool['name'] for tool in COACH_TOOLS])}

When you identify something to log:
1. IMMEDIATELY use the appropriate tool to log the data
2. Explain what you logged after the action
3. Provide encouragement and coaching advice
4. Be proactive - don't ask for permission, just do it and confirm what you did

Example workflow:
User: "I had chicken and rice for lunch"
You: [USE log_meal tool immediately] "Great! I've logged your chicken and rice lunch. Based on my analysis, that's approximately 450 calories with 35g protein - excellent choice for sustained energy!"

BE ACTION-ORIENTED, NOT CONFIRMATION-ORIENTED. Users want their data logged automatically.
"""
    
    # Create a stable base time for all actions in this request
    request_time = datetime.now()
    
    # Call Claude with function calling
    try:
        response = claude_call(
            messages=[{"role": "user", "content": req.message + context}],
            system=system_prompt,
            tools=COACH_TOOLS,
            model="claude-3-5-sonnet-20241022",  # Use Sonnet for better function calling
            metadata={"user_id": user.id, "type": "agentic_coach_chat"}
        )
        
        actions_taken = []
        coach_message = ""
        
        # Process Claude's response and tool calls
        for content_block in response.content:
            if content_block.type == "text":
                coach_message += content_block.text
            elif content_block.type == "tool_use":
                # Handle tool execution
                tool_result = await execute_coach_tool(
                    content_block.name, 
                    content_block.input, 
                    user,
                    request_time
                )
                if tool_result:
                    actions_taken.append(tool_result)
        
        return AgenticCoachResp(
            message=coach_message or "I'm here to help with your health journey!",
            actions_taken=actions_taken,
            disclaimers=guard_result["disclaimers"]
        )
        
    except Exception as e:
        print(f"⚠️  Agentic coach error: {e}")
        return AgenticCoachResp(
            message="I'm having some trouble right now. Could you try rephrasing your message?",
            disclaimers=["This coach provides general wellness guidance only. Consult healthcare providers for medical advice."]
        )

def parse_relative_time(time_mentioned: str, base_time: datetime) -> datetime:
    """Parse relative time mentions into actual timestamps"""
    
    if not time_mentioned:
        # Default to 10 seconds ago from the base time to avoid constantly changing timestamps
        return base_time - timedelta(seconds=10)
    
    time_lower = time_mentioned.lower()
    
    # Morning references
    if any(phrase in time_lower for phrase in ['this morning', 'morning', 'breakfast']):
        return base_time.replace(hour=8, minute=0, second=0, microsecond=0)
    
    # Lunch references  
    elif any(phrase in time_lower for phrase in ['lunch', 'noon', 'midday']):
        return base_time.replace(hour=12, minute=30, second=0, microsecond=0)
    
    # Dinner/evening references
    elif any(phrase in time_lower for phrase in ['dinner', 'evening', 'tonight']):
        return base_time.replace(hour=19, minute=0, second=0, microsecond=0)
    
    # Yesterday references
    elif 'yesterday' in time_lower:
        yesterday = base_time - timedelta(days=1)
        if any(phrase in time_lower for phrase in ['morning']):
            return yesterday.replace(hour=8, minute=0, second=0, microsecond=0)
        elif any(phrase in time_lower for phrase in ['lunch']):
            return yesterday.replace(hour=12, minute=30, second=0, microsecond=0)
        elif any(phrase in time_lower for phrase in ['dinner', 'evening']):
            return yesterday.replace(hour=19, minute=0, second=0, microsecond=0)
        else:
            return yesterday.replace(hour=12, minute=0, second=0, microsecond=0)
    
    # Earlier today
    elif any(phrase in time_lower for phrase in ['earlier', 'before', 'ago']):
        return base_time - timedelta(hours=2)
    
    # Default to base time
    else:
        return base_time

async def execute_coach_tool(tool_name: str, tool_input: dict, user, base_time: datetime) -> LoggedAction:
    """Execute coach tools and return logged action details"""
    try:
        if tool_name == "log_meal":
            meal_desc = tool_input.get("meal_description", "").strip()
            time_mentioned = tool_input.get("time_mentioned")
            
            # Validation
            if not meal_desc:
                raise ValueError("Meal description is required")
            if len(meal_desc) > 500:
                raise ValueError("Meal description too long (max 500 characters)")
            
            # Parse the meal using existing meal parsing
            from tools import text_nutrition
            parsed_meal = text_nutrition.parse(meal_desc, None)
            
            # Validate parsed meal has content
            if not parsed_meal.items:
                raise ValueError("Could not identify any food items in the description")
            
            # Parse the time when the meal was consumed
            meal_time = parse_relative_time(time_mentioned, base_time)
            
            # Create meal object
            meal_id = str(uuid.uuid4())
            result = supabase.table("meals").insert({
                "id": meal_id,
                "user_id": user.id,
                "ts": meal_time.isoformat(),  # Use parsed time instead of now()
                "source": "text",  # Use valid source value instead of "coach"
                "items": [item.__dict__ for item in parsed_meal.items],
                "totals": parsed_meal.totals.__dict__,
                "confidence": parsed_meal.confidence,
                "low_confidence": parsed_meal.low_confidence,
                "notes": f"Logged by AI Coach from: '{meal_desc}'"
            }).execute()
            
            return LoggedAction(
                type="meal",
                id=meal_id,
                summary=f"Logged meal: {parsed_meal.totals.kcal} kcal",
                details={
                    "description": meal_desc,
                    "calories": parsed_meal.totals.kcal,
                    "protein_g": parsed_meal.totals.protein_g,
                    "carbs_g": parsed_meal.totals.carbs_g,
                    "fat_g": parsed_meal.totals.fat_g
                }
            )
            
        elif tool_name == "log_exercise":
            activity = tool_input.get("activity_type", "").strip()
            duration = tool_input.get("duration_minutes", 0)
            intensity = tool_input.get("intensity", "moderate").lower()
            time_mentioned = tool_input.get("time_mentioned")
            
            # Validation
            if not activity:
                raise ValueError("Exercise activity type is required")
            if len(activity) > 100:
                raise ValueError("Exercise activity name too long (max 100 characters)")
            if not isinstance(duration, (int, float)) or duration <= 0:
                raise ValueError("Duration must be a positive number")
            if duration > 1440:  # 24 hours in minutes
                raise ValueError("Duration seems too long (max 24 hours)")
            if intensity not in ["low", "moderate", "high"]:
                intensity = "moderate"  # Default to moderate if invalid
            
            # Estimate calories (simple calculation)
            calorie_rates = {"low": 5, "moderate": 8, "high": 12}  # kcal per minute
            est_kcal = int(duration * calorie_rates.get(intensity, 8))
            
            # Parse the time when the exercise was done
            exercise_time = parse_relative_time(time_mentioned, base_time)
            
            exercise_id = str(uuid.uuid4())
            result = supabase.table("exercises").insert({
                "id": exercise_id,
                "user_id": user.id,
                "ts": exercise_time.isoformat(),  # Use parsed time instead of now()
                "type": activity,
                "duration_min": duration,
                "intensity": intensity,
                "est_kcal": est_kcal
            }).execute()
            
            return LoggedAction(
                type="exercise",
                id=exercise_id,
                summary=f"Logged {activity}: {duration}min, ~{est_kcal} kcal burned",
                details={
                    "activity": activity,
                    "duration_minutes": duration,
                    "intensity": intensity,
                    "calories_burned": est_kcal
                }
            )
            
        elif tool_name == "log_weight":
            weight_kg = tool_input.get("weight_kg", 0)
            time_mentioned = tool_input.get("measurement_time")
            
            # Validation
            if not isinstance(weight_kg, (int, float)) or weight_kg <= 0:
                raise ValueError("Weight must be a positive number")
            if weight_kg < 20 or weight_kg > 300:  # Reasonable human weight range in kg
                raise ValueError("Weight seems unrealistic (20-300 kg range expected)")
            
            # Round to one decimal place for consistency
            weight_kg = round(float(weight_kg), 1)
            
            # Parse the time when the weight was measured
            weight_time = parse_relative_time(time_mentioned, base_time)
            
            weight_id = str(uuid.uuid4())
            result = supabase.table("weights").insert({
                "id": weight_id,
                "user_id": user.id,
                "ts": weight_time.isoformat(),  # Use parsed time instead of now()
                "weight_kg": weight_kg,
                "method": "manual"
            }).execute()
            
            return LoggedAction(
                type="weight",
                id=weight_id,
                summary=f"Logged weight: {weight_kg} kg",
                details={
                    "weight_kg": weight_kg,
                    "method": "AI Coach"
                }
            )
        
        else:
            raise ValueError(f"Unknown tool: {tool_name}")
            
    except Exception as e:
        print(f"⚠️  Tool execution error for {tool_name}: {e}")
        return None

@app.get("/med/next")
async def get_next_med(user=Depends(get_current_user)):
    result = glp1_adherence.get_next_dose({"user_id": user.id})
    return {"next_dose_ts": result["next_due"]}

# History Endpoints

@app.get("/history", response_model=HistoryResp)
async def get_history(
    limit: int = 50,
    offset: int = 0,
    type_filter: Optional[str] = None,
    user=Depends(get_current_user)
):
    """Get user's historical entries (meals, exercises, weights, medications)"""
    entries = []
    
    try:
        # Get meals
        if not type_filter or type_filter == "meal":
            meals = supabase.table("meals").select(
                "id, ts, notes, items"
            ).eq("user_id", user.id).order("ts", desc=True).execute()
            
            for meal in meals.data:
                # Extract food names for better display
                item_names = [item.get("name", "Unknown") for item in meal["items"][:2]]  # Show first 2 items
                if len(meal["items"]) > 2:
                    item_names.append(f"+{len(meal['items']) - 2} more")
                display_name = ", ".join(item_names) if item_names else "Meal"
                
                entries.append(HistoryEntryResp(
                    id=meal["id"],
                    ts=datetime.fromisoformat(meal["ts"].replace("Z", "+00:00")),
                    type="meal",
                    display_name=display_name,
                    details={
                        "items": meal["items"],
                        "notes": meal.get("notes"),
                        "total_kcal": sum(item.get("kcal", 0) for item in meal["items"])
                    }
                ))
        
        # Get exercises
        if not type_filter or type_filter == "exercise":
            exercises = supabase.table("exercises").select(
                "id, ts, type, duration_min, intensity, est_kcal"
            ).eq("user_id", user.id).order("ts", desc=True).execute()
            
            for exercise in exercises.data:
                entries.append(HistoryEntryResp(
                    id=exercise["id"],
                    ts=datetime.fromisoformat(exercise["ts"].replace("Z", "+00:00")),
                    type="exercise",
                    display_name=f"{exercise['type']} - {exercise['duration_min']}min",
                    details={
                        "type": exercise["type"],
                        "duration_min": exercise["duration_min"],
                        "intensity": exercise.get("intensity"),
                        "est_kcal": exercise.get("est_kcal")
                    }
                ))
        
        # Get weights
        if not type_filter or type_filter == "weight":
            weights = supabase.table("weights").select(
                "id, ts, weight_kg, method"
            ).eq("user_id", user.id).order("ts", desc=True).execute()
            
            for weight in weights.data:
                entries.append(HistoryEntryResp(
                    id=weight["id"],
                    ts=datetime.fromisoformat(weight["ts"].replace("Z", "+00:00")),
                    type="weight",
                    display_name=f"Weight - {weight['weight_kg']}kg",
                    details={
                        "weight_kg": weight["weight_kg"],
                        "method": weight["method"]
                    }
                ))
        
        # Sort all entries by timestamp (newest first)
        entries.sort(key=lambda x: x.ts, reverse=True)
        
        # Apply pagination
        total_count = len(entries)
        entries = entries[offset:offset + limit]
        
        return HistoryResp(entries=entries, total_count=total_count)
        
    except Exception as e:
        print(f"❌ Error fetching history: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch history")

@app.put("/history/meal/{entry_id}", response_model=IdResp)
async def update_meal(entry_id: str, req: UpdateMealReq, user=Depends(get_current_user)):
    """Update a meal entry"""
    try:
        # Verify meal belongs to user
        existing = supabase.table("meals").select("user_id").eq("id", entry_id).single().execute()
        if not existing.data or existing.data["user_id"] != user.id:
            raise HTTPException(status_code=404, detail="Meal not found")
        
        # Update meal
        supabase.table("meals").update({
            "items": [item.dict() for item in req.items],
            "notes": req.notes,
            "updated_at": datetime.now().isoformat()
        }).eq("id", entry_id).execute()
        
        return IdResp(id=entry_id)
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error updating meal: {e}")
        raise HTTPException(status_code=500, detail="Failed to update meal")

@app.put("/history/exercise/{entry_id}", response_model=IdResp)
async def update_exercise(entry_id: str, req: UpdateExerciseReq, user=Depends(get_current_user)):
    """Update an exercise entry"""
    try:
        # Verify exercise belongs to user
        existing = supabase.table("exercises").select("user_id").eq("id", entry_id).single().execute()
        if not existing.data or existing.data["user_id"] != user.id:
            raise HTTPException(status_code=404, detail="Exercise not found")
        
        # Update exercise
        supabase.table("exercises").update({
            "type": req.type,
            "duration_min": req.duration_min,
            "intensity": req.intensity,
            "est_kcal": req.est_kcal,
            "updated_at": datetime.now().isoformat()
        }).eq("id", entry_id).execute()
        
        return IdResp(id=entry_id)
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error updating exercise: {e}")
        raise HTTPException(status_code=500, detail="Failed to update exercise")

@app.put("/history/weight/{entry_id}", response_model=IdResp)
async def update_weight(entry_id: str, req: UpdateWeightReq, user=Depends(get_current_user)):
    """Update a weight entry"""
    try:
        # Verify weight belongs to user
        existing = supabase.table("weights").select("user_id").eq("id", entry_id).single().execute()
        if not existing.data or existing.data["user_id"] != user.id:
            raise HTTPException(status_code=404, detail="Weight not found")
        
        # Update weight
        supabase.table("weights").update({
            "weight_kg": req.weight_kg,
            "method": req.method,
            "updated_at": datetime.now().isoformat()
        }).eq("id", entry_id).execute()
        
        return IdResp(id=entry_id)
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error updating weight: {e}")
        raise HTTPException(status_code=500, detail="Failed to update weight")

@app.delete("/history/{entry_type}/{entry_id}")
async def delete_entry(entry_type: str, entry_id: str, user=Depends(get_current_user)):
    """Delete a history entry"""
    try:
        table_map = {
            "meal": "meals",
            "exercise": "exercises", 
            "weight": "weights"
        }
        
        if entry_type not in table_map:
            raise HTTPException(status_code=400, detail="Invalid entry type")
        
        table_name = table_map[entry_type]
        
        # Verify entry belongs to user
        existing = supabase.table(table_name).select("user_id").eq("id", entry_id).single().execute()
        if not existing.data or existing.data["user_id"] != user.id:
            raise HTTPException(status_code=404, detail="Entry not found")
        
        # Delete entry
        supabase.table(table_name).delete().eq("id", entry_id).execute()
        
        return {"message": "Entry deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error deleting entry: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete entry")

@app.get("/health")
async def health():
    """Comprehensive health check endpoint"""
    return await health_checker.run_all_checks()

@app.get("/health/quick")
async def health_quick():
    """Quick health check for load balancer"""
    return {
        "status": "healthy", 
        "timestamp": datetime.now().isoformat(),
        "uptime": metrics_collector.get_metrics()["uptime_human"]
    }

@app.get("/metrics")
async def metrics():
    """Application metrics endpoint"""
    return metrics_collector.get_metrics()