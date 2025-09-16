import re
import html
from typing import Any, Dict, List, Optional
from .logging_config import ValidationError

# Input size limits
MAX_TEXT_LENGTH = 2000
MAX_NAME_LENGTH = 200
MAX_NOTES_LENGTH = 1000
MAX_ITEMS_PER_MEAL = 50
MAX_EXERCISE_DURATION = 1440  # 24 hours in minutes
MAX_WEIGHT_KG = 500  # Reasonable upper limit
MIN_WEIGHT_KG = 20   # Reasonable lower limit

def sanitize_text(text: str, max_length: int = MAX_TEXT_LENGTH) -> str:
    """Sanitize text input by removing HTML and limiting length"""
    if not isinstance(text, str):
        raise ValidationError("Input must be a string")
    
    # Remove HTML tags and decode HTML entities
    clean_text = html.escape(text.strip())
    
    # Remove control characters except newlines and tabs
    clean_text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', clean_text)
    
    # Limit length
    if len(clean_text) > max_length:
        raise ValidationError(f"Text exceeds maximum length of {max_length} characters")
    
    return clean_text

def validate_email(email: str) -> str:
    """Validate and sanitize email address"""
    if not isinstance(email, str):
        raise ValidationError("Email must be a string")
    
    email = email.strip().lower()
    
    # Basic email regex
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if not re.match(email_pattern, email):
        raise ValidationError("Invalid email format")
    
    if len(email) > 254:  # RFC 5321 limit
        raise ValidationError("Email address too long")
    
    return email

def validate_weight(weight_kg: float) -> float:
    """Validate weight measurement"""
    if not isinstance(weight_kg, (int, float)):
        raise ValidationError("Weight must be a number")
    
    weight_kg = float(weight_kg)
    
    if weight_kg < MIN_WEIGHT_KG:
        raise ValidationError(f"Weight too low (minimum {MIN_WEIGHT_KG} kg)")
    
    if weight_kg > MAX_WEIGHT_KG:
        raise ValidationError(f"Weight too high (maximum {MAX_WEIGHT_KG} kg)")
    
    # Round to 1 decimal place
    return round(weight_kg, 1)

def validate_exercise_duration(duration_min: float) -> float:
    """Validate exercise duration"""
    if not isinstance(duration_min, (int, float)):
        raise ValidationError("Duration must be a number")
    
    duration_min = float(duration_min)
    
    if duration_min <= 0:
        raise ValidationError("Duration must be positive")
    
    if duration_min > MAX_EXERCISE_DURATION:
        raise ValidationError(f"Duration too long (maximum {MAX_EXERCISE_DURATION} minutes)")
    
    return duration_min

def validate_calories(kcal: int) -> int:
    """Validate calorie count"""
    if not isinstance(kcal, (int, float)):
        raise ValidationError("Calories must be a number")
    
    kcal = int(kcal)
    
    if kcal < 0:
        raise ValidationError("Calories cannot be negative")
    
    if kcal > 50000:  # Unreasonably high calorie count
        raise ValidationError("Calorie count too high")
    
    return kcal

def validate_macros(protein_g: float, carbs_g: float, fat_g: float) -> tuple:
    """Validate macronutrient values"""
    for name, value in [("protein", protein_g), ("carbs", carbs_g), ("fat", fat_g)]:
        if not isinstance(value, (int, float)):
            raise ValidationError(f"{name} must be a number")
        
        if value < 0:
            raise ValidationError(f"{name} cannot be negative")
        
        if value > 1000:  # Unreasonably high macro count
            raise ValidationError(f"{name} value too high")
    
    return float(protein_g), float(carbs_g), float(fat_g)

def validate_meal_items(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Validate meal items list"""
    if not isinstance(items, list):
        raise ValidationError("Items must be a list")
    
    if len(items) == 0:
        raise ValidationError("Meal must contain at least one item")
    
    if len(items) > MAX_ITEMS_PER_MEAL:
        raise ValidationError(f"Too many items (maximum {MAX_ITEMS_PER_MEAL})")
    
    validated_items = []
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            raise ValidationError(f"Item {i+1} must be an object")
        
        # Validate required fields
        required_fields = ["name", "qty", "unit", "kcal", "protein_g", "carbs_g", "fat_g"]
        for field in required_fields:
            if field not in item:
                raise ValidationError(f"Item {i+1} missing required field: {field}")
        
        # Sanitize and validate each field
        validated_item = {
            "name": sanitize_text(str(item["name"]), MAX_NAME_LENGTH),
            "qty": float(item["qty"]) if item["qty"] > 0 else 0.1,  # Minimum quantity
            "unit": sanitize_text(str(item["unit"]), 20),
            "kcal": validate_calories(item["kcal"]),
            "fdc_id": item.get("fdc_id")
        }
        
        # Validate macros
        validated_item["protein_g"], validated_item["carbs_g"], validated_item["fat_g"] = validate_macros(
            item["protein_g"], item["carbs_g"], item["fat_g"]
        )
        
        validated_items.append(validated_item)
    
    return validated_items

def validate_confidence(confidence: float) -> float:
    """Validate confidence score"""
    if not isinstance(confidence, (int, float)):
        raise ValidationError("Confidence must be a number")
    
    confidence = float(confidence)
    
    if confidence < 0 or confidence > 1:
        raise ValidationError("Confidence must be between 0 and 1")
    
    return confidence

def validate_intensity(intensity: str) -> str:
    """Validate exercise intensity"""
    if not isinstance(intensity, str):
        raise ValidationError("Intensity must be a string")
    
    intensity = intensity.lower().strip()
    
    valid_intensities = ["low", "moderate", "high"]
    if intensity not in valid_intensities:
        raise ValidationError(f"Intensity must be one of: {', '.join(valid_intensities)}")
    
    return intensity

def validate_medication_dose(dose_mg: float) -> float:
    """Validate medication dose"""
    if not isinstance(dose_mg, (int, float)):
        raise ValidationError("Dose must be a number")
    
    dose_mg = float(dose_mg)
    
    if dose_mg <= 0:
        raise ValidationError("Dose must be positive")
    
    if dose_mg > 100:  # Reasonable upper limit for GLP-1 medications
        raise ValidationError("Dose too high")
    
    return round(dose_mg, 2)

def validate_drug_name(drug_name: str) -> str:
    """Validate drug name"""
    drug_name = sanitize_text(drug_name, 100)
    
    # List of known GLP-1 medications
    valid_drugs = [
        "semaglutide", "tirzepatide", "liraglutide", "dulaglutide", 
        "exenatide", "lixisenatide", "ozempic", "wegovy", "mounjaro", 
        "zepbound", "victoza", "saxenda", "trulicity", "byetta", "lyxumia"
    ]
    
    if drug_name.lower() not in valid_drugs and drug_name.lower() != "other":
        # Allow "other" for unlisted medications
        raise ValidationError(f"Unknown medication. Use 'other' for unlisted medications.")
    
    return drug_name.lower()

def validate_image_url(image_url: str) -> str:
    """Validate image URL or base64 data"""
    if not isinstance(image_url, str):
        raise ValidationError("Image URL must be a string")
    
    image_url = image_url.strip()
    
    if len(image_url) == 0:
        raise ValidationError("Image URL cannot be empty")
    
    # Check if it's a data URL (base64)
    if image_url.startswith("data:image/"):
        # Validate data URL format
        if ";base64," not in image_url:
            raise ValidationError("Invalid data URL format")
        
        # Check for reasonable size limit (10MB base64 ≈ 7.5MB image)
        if len(image_url) > 10 * 1024 * 1024:
            raise ValidationError("Image too large (maximum 10MB)")
        
        return image_url
    
    # Validate regular URL
    url_pattern = r'^https?://[^\s]+\.(jpg|jpeg|png|gif|webp)(\?[^\s]*)?$'
    if not re.match(url_pattern, image_url, re.IGNORECASE):
        raise ValidationError("Invalid image URL format")
    
    return image_url

def sanitize_coach_message(message: str) -> str:
    """Sanitize coach chat message"""
    message = sanitize_text(message, MAX_TEXT_LENGTH)
    
    if len(message.strip()) == 0:
        raise ValidationError("Message cannot be empty")
    
    # Check for potential prompt injection patterns
    suspicious_patterns = [
        r'ignore\s+previous\s+instructions',
        r'system\s*:',
        r'assistant\s*:',
        r'user\s*:',
        r'<\s*script',
        r'javascript\s*:',
        r'data\s*:',
    ]
    
    for pattern in suspicious_patterns:
        if re.search(pattern, message, re.IGNORECASE):
            raise ValidationError("Message contains potentially unsafe content")
    
    return message