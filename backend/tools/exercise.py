from typing import Optional, Dict, Any

class ExerciseEstimator:
    def estimate(self, text: str, duration_min: float, intensity: Optional[str] = None, weight_kg: float = 70) -> Dict[str, Any]:
        """
        Estimate calories using MET values and user weight.
        TODO: Integrate Claude for exercise type recognition and MET lookup
        """
        # MET values for common exercises
        met_values = {
            "walking": {"low": 2.5, "moderate": 3.5, "high": 5.0},
            "running": {"low": 6.0, "moderate": 8.5, "high": 11.0},
            "cycling": {"low": 4.0, "moderate": 6.5, "high": 10.0},
            "swimming": {"low": 5.0, "moderate": 7.0, "high": 10.0},
            "strength training": {"low": 3.0, "moderate": 5.0, "high": 8.0},
            "yoga": {"low": 2.0, "moderate": 3.0, "high": 4.0},
            "elliptical": {"low": 4.5, "moderate": 6.5, "high": 8.5}
        }
        
        # Extract exercise type from text
        exercise_type = "walking"  # default
        text_lower = text.lower()
        
        for exercise in met_values.keys():
            if exercise in text_lower:
                exercise_type = exercise
                break
        
        # Get MET value based on intensity
        intensity = intensity or "moderate"
        met = met_values.get(exercise_type, {"moderate": 4.0})[intensity]
        
        # Calculate calories: METs × weight(kg) × time(hours)
        kcal = int(met * weight_kg * (duration_min / 60))
        
        return {
            "kcal": kcal,
            "details": {
                "exercise_type": exercise_type,
                "met_value": met,
                "intensity": intensity,
                "duration_min": duration_min,
                "weight_kg": weight_kg
            }
        }

exercise_estimator = ExerciseEstimator()