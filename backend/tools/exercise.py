from typing import Optional, Dict, Any
import json
try:
    from app.llm import claude_call
except ImportError:
    from backend.app.llm import claude_call

class ExerciseEstimator:
    def estimate(self, text: str, duration_min: float, intensity: Optional[str] = None, weight_kg: float = 70) -> Dict[str, Any]:
        """
        Estimate calories using Claude for exercise recognition and MET values.
        """
        system_prompt = """You are an exercise physiologist analyzing workout descriptions.
        Identify the exercise type and provide the appropriate MET (Metabolic Equivalent of Task) value.
        Return ONLY valid JSON in this exact format with no additional text:
        {
          "exercise_type": "specific exercise name",
          "met_value": numeric MET value,
          "intensity_detected": "low" or "moderate" or "high",
          "confidence": 0.0 to 1.0
        }
        
        Use standard MET values from the Compendium of Physical Activities.
        Examples:
        - Walking (3.5 mph): 4.3 METs
        - Running (6 mph): 9.8 METs
        - Cycling (12-14 mph): 8.0 METs
        - Swimming laps moderate: 7.0 METs
        - Weight training general: 6.0 METs
        - Yoga hatha: 2.5 METs
        """
        
        user_message = f"Exercise description: {text}"
        if intensity:
            user_message += f"\nSpecified intensity: {intensity}"
        else:
            user_message += "\nDetect intensity from description if possible"
        
        try:
            # Call Claude API
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-haiku-20241022",
                metadata={"tool": "exercise_estimator", "text": text[:100]}
            )
            
            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"
            
            # Parse JSON
            try:
                if "```json" in response_text:
                    response_text = response_text.split("```json")[1].split("```")[0]
                elif "```" in response_text:
                    response_text = response_text.split("```")[1].split("```")[0]
                    
                data = json.loads(response_text)
                
                exercise_type = data.get("exercise_type", "general activity")
                met = float(data.get("met_value", 4.0))
                detected_intensity = data.get("intensity_detected", "moderate")
                
                # Use provided intensity if specified, otherwise use detected
                final_intensity = intensity or detected_intensity
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Failed to parse Claude response: {e}")
                return self._fallback_estimate(text, duration_min, intensity, weight_kg)
                
        except Exception as e:
            print(f"Claude API call failed: {e}")
            return self._fallback_estimate(text, duration_min, intensity, weight_kg)
        
        # Calculate calories: METs × weight(kg) × time(hours)
        kcal = int(met * weight_kg * (duration_min / 60))
        
        return {
            "kcal": kcal,
            "details": {
                "exercise_type": exercise_type,
                "met_value": met,
                "intensity": final_intensity,
                "duration_min": duration_min,
                "weight_kg": weight_kg
            }
        }
    
    def _fallback_estimate(self, text: str, duration_min: float, intensity: Optional[str] = None, weight_kg: float = 70) -> Dict[str, Any]:
        """Fallback estimation when Claude is unavailable"""
        # MET values for common exercises
        met_values = {
            "walking": {"low": 2.5, "moderate": 3.5, "high": 5.0},
            "running": {"low": 6.0, "moderate": 8.5, "high": 11.0},
            "cycling": {"low": 4.0, "moderate": 6.5, "high": 10.0},
            "swimming": {"low": 5.0, "moderate": 7.0, "high": 10.0},
            "strength training": {"low": 3.0, "moderate": 5.0, "high": 8.0},
            "weight training": {"low": 3.0, "moderate": 5.0, "high": 8.0},
            "yoga": {"low": 2.0, "moderate": 3.0, "high": 4.0},
            "elliptical": {"low": 4.5, "moderate": 6.5, "high": 8.5},
            "cardio": {"low": 4.0, "moderate": 6.0, "high": 8.0}
        }
        
        # Extract exercise type from text
        exercise_type = "general activity"
        text_lower = text.lower()
        
        for exercise in met_values.keys():
            if exercise in text_lower:
                exercise_type = exercise
                break
        
        # Get MET value based on intensity
        intensity = intensity or "moderate"
        met = met_values.get(exercise_type, {"moderate": 4.0}).get(intensity, 4.0)
        
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