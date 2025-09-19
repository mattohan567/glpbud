from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List
import os
import json
import sentry_sdk
from supabase import create_client, Client
from datetime import datetime, timedelta, date
import uuid
from dotenv import load_dotenv
import pathlib
import logging
import time
from contextlib import asynccontextmanager
from functools import lru_cache

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

# Import database singleton
from .database import SB

# Load environment variables from .env file
# Try to load from parent directory (where .env actually is)
env_path = pathlib.Path(__file__).parent.parent.parent / '.env'
load_dotenv(dotenv_path=env_path)

from .schemas import (
    ParseMealTextReq, ParseMealImageReq, ParseMealAudioReq, MealParse,
    ParseExerciseTextReq, ParseExerciseAudioReq, ExerciseParse,
    LogMealReq, LogExerciseReq, LogWeightReq,
    MedScheduleReq, LogMedEventReq, CoachAskReq,
    IdResp, TodayResp, TrendsResp, CoachResp,
    CoachChatReq, AgenticCoachResp, LoggedAction,
    HistoryResp, HistoryEntryResp, UpdateMealReq, UpdateExerciseReq, UpdateWeightReq,
    WeightPoint, CaloriePoint, StreakInfo, Achievement,
    DailySparkline, MacroTarget, ActivitySummary, NextAction
)
from .llm import claude_call, log_tool_run
try:
    # Try local development import first
    from tools import vision_nutrition, text_nutrition, exercise_estimator, glp1_adherence, insights, safety_guard
except ImportError:
    # Production Docker import
    from backend.tools import vision_nutrition, text_nutrition, exercise_estimator, glp1_adherence, insights, safety_guard

# Initialize logging
logger = setup_logging()

sentry_sdk.init(dsn=os.environ.get("SENTRY_DSN"), traces_sample_rate=0.2)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    try:
        # Warm Supabase connection on startup
        await SB.ping()
        logger.info("[lifespan] Supabase connection warm OK")
    except Exception as e:
        logger.error(f"[lifespan] Warmup failed: {e}")
    yield
    # Cleanup on shutdown if needed
    await SB.dispose()

app = FastAPI(title="GLP-1 Coach API", version="1.0.0", lifespan=lifespan)

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
        
        # Ensure test user exists in our users table
        print(f"🔍 Ensuring test user record exists for {user.email} ({user.id})")
        try:
            # First check if user exists
            existing_user = supabase.table("users").select("id").eq("id", user.id).execute()
            if not existing_user.data:
                # User doesn't exist, try to insert
                supabase.table("users").insert({
                    "id": user.id,
                    "email": user.email,
                    "created_at": datetime.now().isoformat()
                }).execute()
                print(f"✅ Test user record created")
            else:
                print(f"✅ Test user record already exists")
        except Exception as user_error:
            print(f"⚠️  User record operation failed: {user_error}")
            # Try to clean up any orphaned records and recreate
            try:
                print(f"🔄 Attempting to fix user record conflicts")
                # Delete any conflicting records by email (but not user data)
                supabase.table("users").delete().eq("email", user.email).neq("id", user.id).execute()
                # Try insert again
                supabase.table("users").insert({
                    "id": user.id,
                    "email": user.email,
                    "created_at": datetime.now().isoformat()
                }).execute()
                print(f"✅ Test user record recreated successfully")
            except Exception as cleanup_error:
                print(f"❌ Failed to fix user record: {cleanup_error}")
                print(f"⚠️  Continuing anyway - some operations may fail")
        
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
            print(f"✅ Continuing with existing user record - no data will be deleted")
            # SAFETY: Never delete user data - just log and continue
            # User validation succeeded, database record issue is not critical
            
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

@app.post("/parse/meal-audio", response_model=MealParse)
async def parse_meal_audio(req: ParseMealAudioReq, request: Request, user=Depends(get_current_user)):
    """Parse meal from audio recording (supports Romanian!)."""
    # Apply rate limiting for expensive parse operations
    check_rate_limit(request, user.id, 'parse')

    try:
        # Import whisper module
        from .whisper import transcribe_meal_audio

        # Sanitize hints if provided
        clean_hints = sanitize_text(req.hints) if req.hints else None

        logger.info(
            f"Parsing meal audio for user {user.id}",
            extra={
                "user_id": user.id,
                "audio_size": len(req.audio_data) if req.audio_data else 0,
                "has_hints": bool(clean_hints)
            }
        )

        # Transcribe audio to text
        transcribed_text = transcribe_meal_audio(req.audio_data, clean_hints)

        if not transcribed_text:
            raise HTTPException(status_code=400, detail="Failed to transcribe audio")

        logger.info(f"Audio transcribed: {transcribed_text[:100]}...")

        # Parse the transcribed text as a meal
        result = text_nutrition.parse(transcribed_text, clean_hints)

        # Log event for analytics
        supabase.table("event_bus").insert({
            "user_id": user.id,
            "type": "parse_meal_audio",
            "payload": {
                "transcribed_text": transcribed_text[:200],  # First 200 chars for privacy
                "confidence": result.confidence,
                "items_found": len(result.items)
            }
        }).execute()

        return result

    except ValidationError as e:
        logger.warning(f"Meal audio validation failed: {e.message}", extra={"user_id": user.id})
        raise HTTPException(status_code=422, detail={"error": e.error_code, "message": e.message, "field": e.field})
    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is
    except Exception as e:
        log_error(logger, e, {"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to parse meal audio")

@app.post("/transcribe/audio")
async def transcribe_audio_simple(req: ParseMealAudioReq, request: Request, user=Depends(get_current_user)):
    """Simple Whisper transcription without meal parsing."""
    # Apply rate limiting for expensive operations
    check_rate_limit(request, user.id, 'parse')

    try:
        # Import whisper module
        from .whisper import transcribe_audio

        logger.info(
            f"Transcribing audio for user {user.id}",
            extra={
                "user_id": user.id,
                "audio_size": len(req.audio_data) if req.audio_data else 0,
            }
        )

        # Simple transcription to text
        transcribed_text = transcribe_audio(req.audio_data)

        if not transcribed_text:
            raise HTTPException(status_code=400, detail="Failed to transcribe audio")

        logger.info(f"Audio transcribed: {transcribed_text[:100]}...")

        return {"transcription": transcribed_text}

    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is
    except Exception as e:
        log_error(logger, e, {"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to transcribe audio")

@app.post("/parse/exercise-text", response_model=ExerciseParse)
async def parse_exercise_text(req: ParseExerciseTextReq, request: Request, user=Depends(get_current_user)):
    """Parse exercise from text description."""
    # Apply rate limiting for expensive parse operations
    check_rate_limit(request, user.id, 'parse')

    try:
        # Import exercise module
        try:
            from tools.exercise import exercise_estimator
        except ImportError:
            from backend.tools.exercise import exercise_estimator

        # Sanitize input text
        clean_text = sanitize_text(req.text)

        logger.info(
            f"Parsing exercise text for user {user.id}",
            extra={
                "user_id": user.id,
                "text_length": len(clean_text),
                "has_hints": bool(req.hints)
            }
        )

        # Get user weight for calorie calculations
        user_weight = 70  # Default weight
        if hasattr(user, 'profile') and user.profile:
            user_weight = user.profile.get("weight_kg", 70)

        # Parse exercise text
        result = exercise_estimator.parse_exercise_text(clean_text, user_weight)

        if not result or not result.get('exercises'):
            raise HTTPException(status_code=400, detail="Failed to parse exercise description")

        logger.info(f"Exercise parsed: {len(result['exercises'])} exercises, {result['total_kcal']} kcal")

        # Log tool usage for observability
        log_tool_run(
            tool_name="exercise_text_parser",
            input_data={"text": clean_text[:100]},
            output_data={"exercises": len(result['exercises']), "total_kcal": result['total_kcal'], "confidence": result.get('confidence', 0)},
            model="claude-3-5-sonnet-20241022",
            latency_ms=0,  # Will be calculated separately
            success=True,
            user_id=user.id
        )

        return ExerciseParse(**result)

    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is
    except Exception as e:
        log_error(logger, e, {"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to parse exercise text")

@app.post("/parse/exercise-audio", response_model=ExerciseParse)
async def parse_exercise_audio(req: ParseExerciseAudioReq, request: Request, user=Depends(get_current_user)):
    """Parse exercise from audio recording."""
    # Apply rate limiting for expensive operations
    check_rate_limit(request, user.id, 'parse')

    try:
        # Import modules
        from .whisper import transcribe_audio
        try:
            from tools.exercise import exercise_estimator
        except ImportError:
            from backend.tools.exercise import exercise_estimator

        logger.info(
            f"Parsing exercise audio for user {user.id}",
            extra={
                "user_id": user.id,
                "audio_size": len(req.audio_data) if req.audio_data else 0,
                "has_hints": bool(req.hints)
            }
        )

        # Transcribe audio to text
        transcribed_text = transcribe_audio(req.audio_data)

        if not transcribed_text:
            raise HTTPException(status_code=400, detail="Failed to transcribe audio")

        logger.info(f"Audio transcribed: {transcribed_text[:100]}...")

        # Combine transcription with hints
        combined_text = transcribed_text
        if req.hints:
            clean_hints = sanitize_text(req.hints)
            combined_text = f"{transcribed_text}. Additional info: {clean_hints}"

        # Get user weight for calorie calculations
        user_weight = 70  # Default weight
        if hasattr(user, 'profile') and user.profile:
            user_weight = user.profile.get("weight_kg", 70)

        # Parse exercise text
        result = exercise_estimator.parse_exercise_text(combined_text, user_weight)

        if not result or not result.get('exercises'):
            raise HTTPException(status_code=400, detail="Failed to parse exercise from audio")

        logger.info(f"Exercise parsed from audio: {len(result['exercises'])} exercises, {result['total_kcal']} kcal")

        # Log tool usage for observability
        log_tool_run(
            tool_name="exercise_audio_parser",
            input_data={"transcription": transcribed_text[:100]},
            output_data={"exercises": len(result['exercises']), "total_kcal": result['total_kcal'], "confidence": result.get('confidence', 0)},
            model="claude-3-5-sonnet-20241022",
            latency_ms=0,  # Will be calculated separately
            success=True,
            user_id=user.id
        )

        return ExerciseParse(**result)

    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is
    except Exception as e:
        log_error(logger, e, {"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to parse exercise audio")

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
    """Enhanced /today endpoint with comprehensive dashboard data"""
    # Langfuse tracing (commented out for now)
    # from langfuse import trace
    # @trace(name="get_today_enhanced")

    # Get user preferences and targets (with defaults)
    user_profile = {}
    calorie_target = 2000  # Default target
    user_timezone = "UTC"  # Default timezone
    try:
        user_data = supabase.table("users").select("*").eq("id", user.id).single().execute()
        if user_data.data:
            user_profile = user_data.data.get("profile", {})
            calorie_target = user_profile.get("calorie_target", 2000)
            user_timezone = user_data.data.get("timezone", "UTC")
    except Exception as e:
        logger.warning(f"Failed to get user profile: {e}")

    # Calculate today's date in user's timezone
    from zoneinfo import ZoneInfo
    try:
        user_tz = ZoneInfo(user_timezone)
        user_now = datetime.now(user_tz)
        today = user_now.date()

        # Create timezone-aware start/end times
        today_start_local = datetime.combine(today, datetime.min.time()).replace(tzinfo=user_tz)
        # Use start of next day for exclusive end boundary
        tomorrow = today + timedelta(days=1)
        today_end_local = datetime.combine(tomorrow, datetime.min.time()).replace(tzinfo=user_tz)

        # Convert to UTC for database queries (since DB stores in UTC)
        today_start = today_start_local.astimezone(ZoneInfo("UTC")).isoformat()
        today_end = today_end_local.astimezone(ZoneInfo("UTC")).isoformat()

        logger.info(f"User timezone: {user_timezone}, Today range: {today_start} to {today_end}")

    except Exception as timezone_error:
        logger.warning(f"Invalid timezone '{user_timezone}' for user {user.id}, falling back to UTC: {timezone_error}")
        # Fallback to UTC if user timezone is invalid
        today = datetime.now().date()
        today_start = today.isoformat() + "T00:00:00"
        today_end = today.isoformat() + "T23:59:59"

    # Calculate personalized macro targets (40/30/30 split as default)
    targets = MacroTarget(
        calories=calorie_target,
        protein_g=calorie_target * 0.40 / 4,  # 40% protein, 4 cal/g
        carbs_g=calorie_target * 0.30 / 4,     # 30% carbs, 4 cal/g
        fat_g=calorie_target * 0.30 / 9        # 30% fat, 9 cal/g
    )

    # Get today's data
    try:
        # Today's meals
        meals_result = supabase.table("meals").select("*").eq(
            "user_id", user.id
        ).gte("ts", today_start).lt("ts", today_end).order("ts", desc=True).execute()

        todays_meals = meals_result.data or []

        # Calculate meal totals
        kcal_in = sum(meal.get("totals", {}).get("kcal", 0) for meal in todays_meals)
        protein_g = sum(meal.get("totals", {}).get("protein_g", 0) for meal in todays_meals)
        carbs_g = sum(meal.get("totals", {}).get("carbs_g", 0) for meal in todays_meals)
        fat_g = sum(meal.get("totals", {}).get("fat_g", 0) for meal in todays_meals)

        # Today's exercises
        exercises_result = supabase.table("exercises").select("*").eq(
            "user_id", user.id
        ).gte("ts", today_start).lt("ts", today_end).order("ts", desc=True).execute()

        todays_exercises = exercises_result.data or []
        kcal_out = sum(ex.get("est_kcal", 0) for ex in todays_exercises)

    except Exception as e:
        logger.error(f"Today data fetch failed: {e}")
        kcal_in = kcal_out = protein_g = carbs_g = fat_g = 0
        todays_meals = []
        todays_exercises = []

    # Calculate progress percentages
    calorie_progress = min(1.0, (kcal_in - kcal_out) / max(1, targets.calories))
    protein_progress = min(1.0, protein_g / max(1, targets.protein_g))
    carbs_progress = min(1.0, carbs_g / max(1, targets.carbs_g))
    fat_progress = min(1.0, fat_g / max(1, targets.fat_g))

    # Activity summary
    activity = ActivitySummary(
        meals_logged=len(todays_meals),
        exercises_logged=len(todays_exercises),
        water_ml=0,  # TODO: Implement water tracking
        steps=None   # TODO: HealthKit integration
    )

    # Get latest weight and 7-day trend
    latest_weight_kg = None
    weight_trend_7d = None
    try:
        # Latest weight
        weight_result = supabase.table("weights").select("weight_kg").eq(
            "user_id", user.id
        ).order("ts", desc=True).limit(1).execute()

        if weight_result.data:
            latest_weight_kg = weight_result.data[0]["weight_kg"]

            # 7-day old weight for trend
            week_ago = (today - timedelta(days=7)).isoformat()
            old_weight_result = supabase.table("weights").select("weight_kg").eq(
                "user_id", user.id
            ).lte("ts", week_ago + "T23:59:59").order("ts", desc=True).limit(1).execute()

            if old_weight_result.data:
                weight_trend_7d = round(latest_weight_kg - old_weight_result.data[0]["weight_kg"], 1)
    except Exception as e:
        logger.warning(f"Weight data fetch failed: {e}")

    # Generate 7-day sparkline data using user's timezone
    sparkline_dates = []
    sparkline_calories = []
    sparkline_weights = []

    for i in range(6, -1, -1):  # Last 7 days including today
        day = today - timedelta(days=i)
        sparkline_dates.append(day)

        # Create timezone-aware day boundaries for this specific day
        try:
            if user_timezone != "UTC":
                user_tz = ZoneInfo(user_timezone)
                day_start_local = datetime.combine(day, datetime.min.time()).replace(tzinfo=user_tz)
                next_day = day + timedelta(days=1)
                day_end_local = datetime.combine(next_day, datetime.min.time()).replace(tzinfo=user_tz)
                day_start = day_start_local.astimezone(ZoneInfo("UTC")).isoformat()
                day_end = day_end_local.astimezone(ZoneInfo("UTC")).isoformat()
            else:
                day_start = day.isoformat() + "T00:00:00"
                day_end = day.isoformat() + "T23:59:59"
        except Exception:
            # Fallback to simple day boundaries
            day_start = day.isoformat() + "T00:00:00"
            day_end = day.isoformat() + "T23:59:59"

        try:
            # Try analytics table first (pre-computed)
            analytics_result = supabase.table("analytics_daily").select("kcal_in, kcal_out").eq(
                "user_id", user.id
            ).eq("day", day.isoformat()).single().execute()

            if analytics_result.data:
                net_cal = analytics_result.data["kcal_in"] - analytics_result.data["kcal_out"]
            else:
                # Fallback to calculating from raw data
                meals_cal = supabase.table("meals").select("totals").eq(
                    "user_id", user.id
                ).gte("ts", day_start).lt("ts", day_end).execute()

                day_kcal_in = sum(m.get("totals", {}).get("kcal", 0) for m in meals_cal.data or [])

                ex_cal = supabase.table("exercises").select("est_kcal").eq(
                    "user_id", user.id
                ).gte("ts", day_start).lt("ts", day_end).execute()

                day_kcal_out = sum(e.get("est_kcal", 0) for e in ex_cal.data or [])
                net_cal = day_kcal_in - day_kcal_out

            sparkline_calories.append(net_cal)

            # Get weight for that day if exists
            weight_day = supabase.table("weights").select("weight_kg").eq(
                "user_id", user.id
            ).gte("ts", day_start).lt("ts", day_end).order("ts", desc=True).limit(1).execute()

            sparkline_weights.append(weight_day.data[0]["weight_kg"] if weight_day.data else None)

        except Exception:
            sparkline_calories.append(0)
            sparkline_weights.append(None)

    sparkline = DailySparkline(
        dates=sparkline_dates,
        calories=sparkline_calories,
        weights=sparkline_weights
    )

    # Calculate current streak
    streak_days = 0
    try:
        # Simple approach: count consecutive days with any activity
        for i in range(30):  # Check last 30 days max
            check_day = today - timedelta(days=i)
            day_start = check_day.isoformat() + "T00:00:00"
            day_end = check_day.isoformat() + "T23:59:59"

            # Check if any meal or exercise on that day
            has_activity = supabase.table("meals").select("id").eq(
                "user_id", user.id
            ).gte("ts", day_start).lt("ts", day_end).limit(1).execute()

            if has_activity.data:
                streak_days += 1
            else:
                if i > 0:  # Don't break on today if no activity yet
                    break
    except Exception:
        pass

    # Generate smart daily tip using Claude (or use fallback)
    daily_tip = None
    try:
        if kcal_in > 0:  # Only generate tip if user has logged something
            # Use cached tip if recent (within last 6 hours)
            # For now, use simple rule-based tips
            if calorie_progress > 1.1:
                daily_tip = "You're over your calorie target today. Consider a lighter dinner or add some exercise!"
            elif protein_progress < 0.5 and len(todays_meals) < 3:
                daily_tip = "You're under 50% of your protein goal. Try adding lean protein to your next meal!"
            elif streak_days >= 7:
                daily_tip = f"Amazing {streak_days}-day streak! Consistency is the key to lasting results!"
            elif len(todays_exercises) == 0:
                daily_tip = "No exercise logged today. Even a 10-minute walk makes a difference!"
            else:
                daily_tip = "Great progress today! Keep logging to stay on track!"
    except Exception:
        pass

    # Generate suggested next actions
    next_actions = []
    current_hour = datetime.now().hour

    # Meal suggestions based on time
    if current_hour < 10 and len([m for m in todays_meals if "breakfast" in str(m).lower()]) == 0:
        next_actions.append(NextAction(
            type="log_meal",
            title="Log Breakfast",
            subtitle="Start your day right",
            icon="sun.max.fill"
        ))
    elif 11 <= current_hour < 14 and len([m for m in todays_meals if any(x in str(m).lower() for x in ["lunch", "noon"])]) == 0:
        next_actions.append(NextAction(
            type="log_meal",
            title="Log Lunch",
            subtitle="Track your midday meal",
            icon="sun.dust.fill"
        ))
    elif current_hour >= 17 and len([m for m in todays_meals if any(x in str(m).lower() for x in ["dinner", "evening"])]) == 0:
        next_actions.append(NextAction(
            type="log_meal",
            title="Log Dinner",
            subtitle="Don't forget dinner",
            icon="moon.fill"
        ))

    # Exercise suggestion if none logged
    if len(todays_exercises) == 0 and current_hour < 20:
        next_actions.append(NextAction(
            type="log_exercise",
            title="Log Today's Activity",
            subtitle="Every step counts",
            icon="figure.walk"
        ))

    # Weight suggestion if not logged recently
    try:
        last_weight = supabase.table("weights").select("ts").eq(
            "user_id", user.id
        ).order("ts", desc=True).limit(1).execute()

        if not last_weight.data or (datetime.now() - datetime.fromisoformat(last_weight.data[0]["ts"].replace("Z", "+00:00"))).days > 2:
            if current_hour < 10:  # Morning is best for weight
                next_actions.append(NextAction(
                    type="log_weight",
                    title="Log Morning Weight",
                    subtitle="Best time for consistency",
                    icon="scalemass.fill"
                ))
    except Exception:
        pass

    # Medication reminder
    next_dose_ts = None
    medication_adherence_pct = 100.0
    try:
        medications = supabase.table("medications").select("*").eq(
            "user_id", user.id
        ).eq("active", True).execute()

        if medications.data:
            next_dose_result = glp1_adherence.get_next_dose({"user_id": user.id})
            next_dose_ts = next_dose_result.get("next_due")

            if next_dose_ts and datetime.fromisoformat(next_dose_ts) < datetime.now() + timedelta(hours=4):
                next_actions.insert(0, NextAction(  # Priority action
                    type="take_medication",
                    title="Medication Due Soon",
                    subtitle=medications.data[0]["drug_name"].title(),
                    time_due=datetime.fromisoformat(next_dose_ts),
                    icon="cross.fill"
                ))

            # Calculate adherence (simplified - would need med_events table analysis)
            # For now just return default
            medication_adherence_pct = 100.0
    except Exception as e:
        logger.warning(f"Medication check failed: {e}")

    # Build timeline of all today's activities
    timeline_events = []
    for meal in todays_meals:
        timeline_events.append({
            "type": "meal",
            "ts": meal["ts"],
            "data": meal
        })
    for exercise in todays_exercises:
        timeline_events.append({
            "type": "exercise",
            "ts": exercise["ts"],
            "data": exercise
        })

    # Sort timeline by timestamp
    timeline_events.sort(key=lambda x: x["ts"], reverse=True)
    last_logs = timeline_events[:10]  # Last 10 events

    return TodayResp(
        date=today,
        # Current totals
        kcal_in=kcal_in,
        kcal_out=kcal_out,
        protein_g=protein_g,
        carbs_g=carbs_g,
        fat_g=fat_g,
        water_ml=0,  # TODO: Implement

        # Personalized targets
        targets=targets,

        # Progress percentages
        calorie_progress=calorie_progress,
        protein_progress=protein_progress,
        carbs_progress=carbs_progress,
        fat_progress=fat_progress,
        water_progress=0.0,

        # Activity summary
        activity=activity,

        # Medication tracking
        next_dose_ts=next_dose_ts,
        medication_adherence_pct=medication_adherence_pct,

        # Recent activity timeline
        last_logs=last_logs,
        todays_meals=todays_meals,
        todays_exercises=todays_exercises,

        # 7-day sparkline data
        sparkline=sparkline,

        # Weight tracking
        latest_weight_kg=latest_weight_kg,
        weight_trend_7d=weight_trend_7d,

        # Smart insights
        daily_tip=daily_tip,
        streak_days=streak_days,

        # Suggested next actions
        next_actions=next_actions
    )

def calculate_streaks(user_id: str) -> List[StreakInfo]:
    """Calculate current and longest streaks for different activity types"""
    streaks = []

    try:
        # Get all activity dates grouped by type
        activities = {
            "meals": supabase.table("meals").select("ts").eq("user_id", user_id).order("ts", desc=True).execute(),
            "exercise": supabase.table("exercises").select("ts").eq("user_id", user_id).order("ts", desc=True).execute(),
            "weight": supabase.table("weights").select("ts").eq("user_id", user_id).order("ts", desc=True).execute()
        }

        # Calculate overall logging streak (any activity)
        all_dates = set()
        for activity_data in activities.values():
            for record in activity_data.data or []:
                all_dates.add(datetime.fromisoformat(record["ts"].replace("Z", "+00:00")).date())

        logging_streak = calculate_consecutive_days(sorted(all_dates, reverse=True))
        last_activity_dt = None
        if all_dates:
            # Convert date to datetime with timezone and normalize microseconds
            last_date = max(all_dates)
            last_activity_dt = datetime.combine(last_date, datetime.min.time()).replace(
                tzinfo=datetime.now().astimezone().tzinfo,
                microsecond=0
            )

        streaks.append(StreakInfo(
            type="logging",
            current_streak=logging_streak["current"],
            longest_streak=logging_streak["longest"],
            last_activity=last_activity_dt
        ))

        # Calculate individual activity streaks
        for activity_type, activity_data in activities.items():
            dates = set()
            for record in activity_data.data or []:
                dates.add(datetime.fromisoformat(record["ts"].replace("Z", "+00:00")).date())

            streak = calculate_consecutive_days(sorted(dates, reverse=True))
            last_activity_dt = None
            if dates:
                # Convert date to datetime with timezone and normalize microseconds
                last_date = max(dates)
                last_activity_dt = datetime.combine(last_date, datetime.min.time()).replace(
                    tzinfo=datetime.now().astimezone().tzinfo,
                    microsecond=0
                )

            streaks.append(StreakInfo(
                type=activity_type,
                current_streak=streak["current"],
                longest_streak=streak["longest"],
                last_activity=last_activity_dt
            ))

    except Exception as e:
        logger.error(f"Streak calculation error: {e}")

    return streaks

def calculate_consecutive_days(sorted_dates: List[date]) -> dict:
    """Calculate current and longest streak from sorted dates (newest first)"""
    if not sorted_dates:
        return {"current": 0, "longest": 0}

    current_streak = 0
    longest_streak = 0
    temp_streak = 0

    # Check if today or yesterday has activity (for current streak)
    today = date.today()
    yesterday = today - timedelta(days=1)

    if sorted_dates[0] == today or sorted_dates[0] == yesterday:
        expected_date = sorted_dates[0]
        for activity_date in sorted_dates:
            if activity_date == expected_date:
                current_streak += 1
                expected_date -= timedelta(days=1)
            else:
                break

    # Calculate longest streak
    if len(sorted_dates) > 0:
        temp_streak = 1
        for i in range(1, len(sorted_dates)):
            if sorted_dates[i-1] - sorted_dates[i] == timedelta(days=1):
                temp_streak += 1
            else:
                longest_streak = max(longest_streak, temp_streak)
                temp_streak = 1
        longest_streak = max(longest_streak, temp_streak)

    return {"current": current_streak, "longest": longest_streak}

def generate_achievements(user_id: str, streaks: List[StreakInfo]) -> List[Achievement]:
    """Generate achievement badges based on user activity"""
    achievements = []

    # Streak-based achievements
    for streak in streaks:
        if streak.current_streak >= 7:
            achievements.append(Achievement(
                id=f"{streak.type}_week_streak",
                title=f"🔥 Week {streak.type.title()} Streak",
                description=f"Logged {streak.type} for 7 consecutive days",
                earned_at=datetime.now(datetime.now().astimezone().tzinfo).replace(microsecond=0),
                progress=1.0
            ))

        if streak.current_streak >= 30:
            achievements.append(Achievement(
                id=f"{streak.type}_month_streak",
                title=f"🏆 Month {streak.type.title()} Streak",
                description=f"Logged {streak.type} for 30 consecutive days",
                earned_at=datetime.now(datetime.now().astimezone().tzinfo).replace(microsecond=0),
                progress=1.0
            ))

    return achievements

def generate_insights(user_id: str, weight_trend: List[WeightPoint], calorie_trend: List[CaloriePoint]) -> List[str]:
    """Generate smart insights based on user data"""
    insights = []

    try:
        # Weight trend insights
        if len(weight_trend) >= 7:
            recent_weights = [p.weight_kg for p in weight_trend[-7:]]
            weight_change = recent_weights[-1] - recent_weights[0]

            if weight_change < -0.5:
                insights.append(f"📉 Great progress! Down {abs(weight_change):.1f}kg this week")
            elif weight_change > 0.5:
                insights.append(f"📈 Weight up {weight_change:.1f}kg this week - consider reviewing your goals")
            else:
                insights.append("⚖️ Weight stable this week - consistency is key!")

        # Calorie trend insights
        if len(calorie_trend) >= 3:
            avg_deficit = sum(p.net for p in calorie_trend[-3:]) / 3
            if avg_deficit < -200:
                insights.append("🎯 Good calorie deficit - staying on track!")
            elif avg_deficit > 200:
                insights.append("⚠️ Calorie surplus detected - consider adjusting portions")

        # Activity consistency
        recent_days_with_data = len([p for p in calorie_trend[-7:] if p.intake > 0])
        if recent_days_with_data >= 5:
            insights.append("📊 Excellent logging consistency this week!")

    except Exception as e:
        logger.error(f"Insight generation error: {e}")

    return insights

@app.get("/trends", response_model=TrendsResp)
async def get_trends(range: str = "7d", user=Depends(get_current_user)):
    """Enhanced trends endpoint with streaks and insights"""
    try:
        days = {"3d": 3, "7d": 7, "30d": 30, "90d": 90, "all": 365*10}.get(range, 7)  # "all" = 10 years
        start_date = datetime.now().date() - timedelta(days=days)

        # Get weight data
        weights_data = supabase.table("weights").select("ts, weight_kg").eq(
            "user_id", user.id
        ).gte("ts", start_date.isoformat()).order("ts").execute()

        weight_trend = []
        for w in weights_data.data or []:
            # Parse datetime and normalize to remove microseconds for consistent formatting
            dt = datetime.fromisoformat(w["ts"].replace("Z", "+00:00"))
            # Remove microseconds to ensure consistent ISO8601 formatting without fractional seconds
            dt = dt.replace(microsecond=0)
            weight_trend.append(WeightPoint(
                date=dt,
                weight_kg=w["weight_kg"]
            ))

        # Get calorie data from analytics or calculate from raw data
        analytics_data = supabase.table("analytics_daily").select("*").eq(
            "user_id", user.id
        ).gte("day", start_date.isoformat()).order("day").execute()

        calorie_trend = []
        for a in analytics_data.data or []:
            intake = a.get("kcal_in", 0)
            burned = a.get("kcal_out", 0)
            # Parse datetime and normalize to remove microseconds for consistent formatting
            dt = datetime.fromisoformat(a["day"] + "T00:00:00+00:00")
            # Remove microseconds to ensure consistent ISO8601 formatting without fractional seconds
            dt = dt.replace(microsecond=0)
            calorie_trend.append(CaloriePoint(
                date=dt,
                intake=intake,
                burned=burned,
                net=intake - burned
            ))

        # Calculate streaks
        streaks = calculate_streaks(user.id)

        # Generate achievements
        achievements = generate_achievements(user.id, streaks)

        # Generate insights
        insights = generate_insights(user.id, weight_trend, calorie_trend)

        return TrendsResp(
            weight_trend=weight_trend,
            calorie_trend=calorie_trend,
            current_streaks=streaks,
            achievements=achievements,
            insights=insights
        )

    except Exception as e:
        logger.error(f"Trends error: {e}", extra={"user_id": user.id})
        raise HTTPException(status_code=500, detail="Failed to fetch trends data")

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
        # Safety guard blocked the request
        safety_message = guard_result.get("reasoning", "This request cannot be processed for safety reasons.")
        return AgenticCoachResp(
            message=safety_message,
            actions_taken=[],
            disclaimers=guard_result.get("disclaimers", [
                "I'm designed to provide general health and wellness information only.",
                "Always consult with healthcare professionals for medical advice."
            ])
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

# 200ms cache to prevent health check stampedes
@lru_cache(maxsize=1)
def _health_cache_bucket():
    return int(time.time()*5)  # 200ms buckets

@app.get("/health")
async def health():
    """Optimized health check endpoint with caching"""
    _ = _health_cache_bucket()  # Cache key
    try:
        # Use lightweight ping instead of full checks
        ok = await SB.ping()
        return {
            "status": "healthy" if ok else "unhealthy",
            "database": "connected" if ok else "disconnected",
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {"status": "unhealthy", "error": str(e)}, 503

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