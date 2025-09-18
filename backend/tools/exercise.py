from typing import Optional, Dict, Any, List
import json
try:
    from app.llm import claude_call
except ImportError:
    from backend.app.llm import claude_call

class ExerciseEstimator:
    def parse_exercise_text(self, text: str, weight_kg: float = 70) -> Dict[str, Any]:
        """
        Parse natural language exercise descriptions into structured data.
        """
        system_prompt = """You are a fitness coach analyzing workout descriptions.
        Parse the exercise description into structured data.

        Return ONLY valid JSON in this exact format with no additional text:
        {
          "exercises": [
            {
              "name": "specific exercise name",
              "category": "cardio" or "strength" or "flexibility" or "sport",
              "duration_min": numeric minutes or null,
              "sets": numeric sets or null,
              "reps": numeric reps or null,
              "weight_kg": numeric weight or null,
              "intensity": "low" or "moderate" or "high",
              "equipment": "equipment name" or "none",
              "est_kcal": estimated calories for this exercise
            }
          ],
          "total_duration_min": total workout duration,
          "total_kcal": total estimated calories,
          "confidence": 0.0 to 1.0
        }

        Exercise categories:
        - cardio: running, cycling, swimming, walking, dancing
        - strength: weight lifting, bodyweight exercises, resistance training
        - flexibility: yoga, stretching, pilates
        - sport: tennis, basketball, soccer, etc.

        Use standard MET values to estimate calories:
        - Light cardio (walking): 3-4 METs
        - Moderate cardio (jogging): 6-8 METs
        - Vigorous cardio (running): 9-12 METs
        - Strength training: 5-8 METs
        - Yoga/stretching: 2-4 METs

        Calories = METs × weight_kg × duration_hours
        """

        user_message = f"Exercise description: {text}\nUser weight: {weight_kg} kg"

        try:
            # Call Claude API
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-sonnet-20241022",  # Use Sonnet for better parsing
                metadata={"tool": "exercise_parser", "text": text[:100]}
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

                # Validate and return structured data
                exercises = data.get("exercises", [])
                total_duration = data.get("total_duration_min", 0)
                total_kcal = data.get("total_kcal", 0)
                confidence = data.get("confidence", 0.7)

                return {
                    "exercises": exercises,
                    "total_duration_min": total_duration,
                    "total_kcal": total_kcal,
                    "confidence": confidence,
                    "questions": [],
                    "low_confidence": confidence < 0.6
                }

            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Failed to parse Claude response: {e}")
                return self._fallback_parse(text, weight_kg)

        except Exception as e:
            print(f"Claude API call failed: {e}")
            return self._fallback_parse(text, weight_kg)

    def _fallback_parse(self, text: str, weight_kg: float = 70) -> Dict[str, Any]:
        """Fallback exercise parsing when Claude is unavailable"""
        # Extract basic exercise information using keyword matching
        text_lower = text.lower()

        # Common exercise patterns
        exercises = []
        total_duration = 30  # Default duration
        total_kcal = 0

        # Extract duration if mentioned
        import re
        duration_match = re.search(r'(\d+)\s*(min|minute|minutes|hour|hours)', text_lower)
        if duration_match:
            duration_value = int(duration_match.group(1))
            unit = duration_match.group(2)
            if 'hour' in unit:
                total_duration = duration_value * 60
            else:
                total_duration = duration_value

        # Exercise type detection
        exercise_types = {
            'running': {'category': 'cardio', 'met': 8.0},
            'jogging': {'category': 'cardio', 'met': 6.0},
            'walking': {'category': 'cardio', 'met': 3.5},
            'cycling': {'category': 'cardio', 'met': 6.5},
            'swimming': {'category': 'cardio', 'met': 7.0},
            'yoga': {'category': 'flexibility', 'met': 3.0},
            'strength': {'category': 'strength', 'met': 6.0},
            'weight': {'category': 'strength', 'met': 6.0},
            'cardio': {'category': 'cardio', 'met': 6.0},
            'elliptical': {'category': 'cardio', 'met': 6.5}
        }

        detected_exercise = "general activity"
        exercise_info = {'category': 'cardio', 'met': 4.0}

        for exercise, info in exercise_types.items():
            if exercise in text_lower:
                detected_exercise = exercise
                exercise_info = info
                break

        # Calculate calories
        kcal = int(exercise_info['met'] * weight_kg * (total_duration / 60))

        exercises.append({
            'name': detected_exercise,
            'category': exercise_info['category'],
            'duration_min': total_duration,
            'sets': None,
            'reps': None,
            'weight_kg': None,
            'intensity': 'moderate',
            'equipment': 'none',
            'est_kcal': kcal
        })

        return {
            'exercises': exercises,
            'total_duration_min': total_duration,
            'total_kcal': kcal,
            'confidence': 0.5,  # Lower confidence for fallback
            'questions': [],
            'low_confidence': True
        }

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