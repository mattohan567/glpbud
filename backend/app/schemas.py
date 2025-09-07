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
    image_url: HttpUrl
    user_id: Optional[str] = None
    hints: Optional[str] = None

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

class TodayResp(BaseModel):
    date: date
    kcal_in: int
    kcal_out: int
    protein_g: float
    carbs_g: float
    fat_g: float
    next_dose_ts: Optional[datetime] = None
    last_logs: List[dict]

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