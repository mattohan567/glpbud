from typing import List, Optional, Literal
from pydantic import BaseModel, Field, HttpUrl
from datetime import datetime, date

class MacroTotals(BaseModel):
    kcal: int = Field(..., ge=0)
    protein_g: float = Field(..., ge=0)
    carbs_g: float = Field(..., ge=0)
    fat_g: float = Field(..., ge=0)

class MealItem(BaseModel):
    name: str
    qty: float
    unit: str
    kcal: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fdc_id: Optional[int] = None

class MealParse(BaseModel):
    items: List[MealItem]
    totals: MacroTotals
    confidence: float = Field(..., ge=0, le=1)
    questions: Optional[List[str]] = None
    low_confidence: bool = False

class ParseMealTextReq(BaseModel):
    text: str
    user_id: Optional[str] = None
    hints: Optional[str] = None

class ParseMealImageReq(BaseModel):
    image_url: str  # Changed from HttpUrl to str to support base64 data URLs
    user_id: Optional[str] = None
    hints: Optional[str] = None

class ParseMealAudioReq(BaseModel):
    audio_data: str  # base64 encoded audio data
    user_id: Optional[str] = None
    hints: Optional[str] = None

class FixMealParseReq(BaseModel):
    original_parse: MealParse
    fix_prompt: str  # User description of what needs to be fixed

class FixMealResp(BaseModel):
    updated_parse: MealParse
    changes_applied: List[str]

class FixItemReq(BaseModel):
    original_item: MealItem
    fix_prompt: str  # User description of what needs to be fixed
    meal_context: Optional[List[MealItem]] = None  # Other items for context

class FixItemResp(BaseModel):
    updated_item: MealItem
    changes_applied: List[str]

class AddFoodReq(BaseModel):
    food_description: str  # Natural language description of food to add
    existing_items: Optional[List[MealItem]] = None  # Current meal context

class AddFoodResp(BaseModel):
    new_item: MealItem  # List of changes that were made

class LogMealReq(BaseModel):
    datetime: datetime
    source: Literal["image","text","manual"]
    parse: MealParse
    notes: Optional[str] = None

class LogExerciseReq(BaseModel):
    datetime: datetime
    type: str
    duration_min: float
    intensity: Optional[Literal["low","moderate","high"]] = None
    est_kcal: Optional[int] = None
    source_text: Optional[str] = None

class LogWeightReq(BaseModel):
    datetime: datetime
    weight_kg: float
    method: Optional[Literal["scale","manual","healthkit"]] = "manual"

class ExerciseItem(BaseModel):
    name: str
    category: str  # cardio, strength, flexibility, sport
    duration_min: Optional[float] = None
    sets: Optional[int] = None
    reps: Optional[int] = None
    weight_kg: Optional[float] = None
    intensity: str  # low, moderate, high
    equipment: Optional[str] = None
    est_kcal: int

class ExerciseParse(BaseModel):
    exercises: List[ExerciseItem]
    total_duration_min: float
    total_kcal: int
    confidence: float = Field(..., ge=0, le=1)
    questions: Optional[List[str]] = None
    low_confidence: bool = False

class ParseExerciseTextReq(BaseModel):
    text: str
    user_id: Optional[str] = None
    hints: Optional[str] = None

class ParseExerciseAudioReq(BaseModel):
    audio_data: str  # base64 encoded audio data
    user_id: Optional[str] = None
    hints: Optional[str] = None

class MedScheduleReq(BaseModel):
    drug_name: Literal["semaglutide","tirzepatide","liraglutide","other"]
    dose_mg: float
    schedule_rule: str
    start_ts: datetime
    notes: Optional[str] = None

class LogMedEventReq(BaseModel):
    datetime: datetime
    drug_name: str
    dose_mg: float
    injection_site: Optional[Literal["LLQ","RLQ","LUQ","RUQ","thigh_left","thigh_right","arm_left","arm_right"]] = None
    side_effects: Optional[List[str]] = None
    notes: Optional[str] = None

class CoachAskReq(BaseModel):
    question: str
    context_opt_in: bool = True

class IdResp(BaseModel):
    ok: bool = True
    id: str

# Enhanced Today Response with comprehensive dashboard data
class DailySparkline(BaseModel):
    """7-day mini trend data for sparkline visualization"""
    dates: List[date]
    calories: List[int]  # Net calories per day
    weights: List[Optional[float]]  # May have null values for missing days

class MacroTarget(BaseModel):
    """Personalized macro nutrient targets"""
    protein_g: float
    carbs_g: float
    fat_g: float
    calories: int

class ActivitySummary(BaseModel):
    """Summary of today's activities"""
    meals_logged: int
    exercises_logged: int
    water_ml: int = 0  # Default 0 until we implement water tracking
    steps: Optional[int] = None  # From HealthKit if available

class NextAction(BaseModel):
    """Suggested next action for user"""
    type: Literal["log_meal", "log_exercise", "log_weight", "take_medication", "drink_water"]
    title: str
    subtitle: Optional[str] = None
    time_due: Optional[datetime] = None
    icon: str  # SF Symbol name

class TodayResp(BaseModel):
    date: date
    # Current totals
    kcal_in: int
    kcal_out: int
    protein_g: float
    carbs_g: float
    fat_g: float
    water_ml: int = 0  # Default 0 until implemented

    # Personalized targets
    targets: MacroTarget

    # Progress percentages (0-1.0)
    calorie_progress: float
    protein_progress: float
    carbs_progress: float
    fat_progress: float
    water_progress: float = 0.0

    # Activity summary
    activity: ActivitySummary

    # Medication tracking
    next_dose_ts: Optional[datetime] = None
    medication_adherence_pct: float = 100.0  # Default 100% until we track

    # Recent activity timeline
    last_logs: List[dict]
    todays_meals: List[dict] = []  # Full meal objects for timeline
    todays_exercises: List[dict] = []  # Full exercise objects for timeline

    # 7-day sparkline data
    sparkline: DailySparkline

    # Weight tracking
    latest_weight_kg: Optional[float] = None
    weight_trend_7d: Optional[float] = None  # +/- kg change over 7 days

    # Smart insights
    daily_tip: Optional[str] = None  # AI-generated contextual tip
    streak_days: int = 0  # Current logging streak

    # Suggested next actions
    next_actions: List[NextAction] = []

class TrendsResp(BaseModel):
    range: str
    weight_series: List[dict]
    kcal_in_series: List[dict]
    kcal_out_series: List[dict]
    protein_series: List[dict]

class CoachResp(BaseModel):
    answer: str
    disclaimers: List[str] = []
    references: List[str] = []

class CoachChatReq(BaseModel):
    message: str
    context_opt_in: bool = True

class LoggedAction(BaseModel):
    type: Literal["meal", "exercise", "weight"]
    id: str
    summary: str
    details: dict

class AgenticCoachResp(BaseModel):
    message: str
    actions_taken: List[LoggedAction] = []
    disclaimers: List[str] = []

class HistoryEntryResp(BaseModel):
    id: str
    ts: datetime
    type: Literal["meal", "exercise", "weight", "medication"]
    display_name: str
    details: dict

class HistoryResp(BaseModel):
    entries: List[HistoryEntryResp]
    total_count: int

class UpdateMealReq(BaseModel):
    items: List[MealItem]
    notes: Optional[str] = None

class UpdateExerciseReq(BaseModel):
    type: str
    duration_min: float
    intensity: Optional[Literal["low","moderate","high"]] = None
    est_kcal: Optional[int] = None

class UpdateWeightReq(BaseModel):
    weight_kg: float
    method: Optional[Literal["scale","manual","healthkit"]] = "manual"

# Trends and Streaks DTOs
class WeightPoint(BaseModel):
    date: datetime
    weight_kg: float

class CaloriePoint(BaseModel):
    date: datetime
    intake: int
    burned: int
    net: int

class StreakInfo(BaseModel):
    type: Literal["logging", "meals", "exercise", "weight"]
    current_streak: int
    longest_streak: int
    last_activity: Optional[datetime] = None

class Achievement(BaseModel):
    id: str
    title: str
    description: str
    earned_at: Optional[datetime] = None
    progress: float  # 0.0 to 1.0

class TrendsResp(BaseModel):
    weight_trend: List[WeightPoint]
    calorie_trend: List[CaloriePoint]
    current_streaks: List[StreakInfo]
    achievements: List[Achievement]
    insights: List[str]

class DeleteEntryReq(BaseModel):
    entry_id: str
    entry_type: Literal["meal", "exercise", "weight", "medication"]