from typing import Dict, Any, List

class Insights:
    def generate(self, user_id: str, window: str = "7d") -> Dict[str, Any]:
        """
        Generate weekly insights and actionable nudges.
        TODO: Integrate with actual user data and Claude for personalized insights
        """
        # Dummy implementation - replace with actual data analysis
        bullets = [
            "You averaged 1,650 kcal/day this week (15% below target)",
            "Protein intake improved: 92g daily average (hit target 5/7 days)",
            "Most consistent logging time: 7-9 PM (consider pre-logging dinner)"
        ]
        
        flags = [
            {"type": "positive", "message": "3-day logging streak! Keep it up"},
            {"type": "caution", "message": "Weight trend suggests faster loss than recommended"}
        ]
        
        return {
            "bullets": bullets,
            "flags": flags
        }

class SafetyGuard:
    def check(self, message: str, user_ctx: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate safety and produce disclaimers before coaching responses.
        TODO: Integrate Claude for sophisticated safety checking
        """
        # Keywords that trigger medical disclaimers
        medical_keywords = [
            "dose", "medication", "side effect", "nausea", "vomiting",
            "heart", "blood pressure", "diabetes", "pregnant", "surgery"
        ]
        
        disclaimers = []
        redactions = []
        allow = True
        
        message_lower = message.lower()
        
        # Check for medical advice requests
        for keyword in medical_keywords:
            if keyword in message_lower:
                disclaimers.append(
                    "This information is for educational purposes only. "
                    "Always consult your healthcare provider for medical advice."
                )
                break
        
        # Check for extreme calorie targets
        if "1200" in message or "1000" in message:
            disclaimers.append(
                "Very low calorie diets should only be followed under medical supervision."
            )
        
        # Block direct medical prescriptions
        if any(phrase in message_lower for phrase in ["should i take", "can i stop", "change my dose"]):
            allow = False
            disclaimers.append(
                "I cannot provide specific medical advice. Please consult your healthcare provider."
            )
        
        return {
            "allow": allow,
            "redactions": redactions,
            "disclaimers": disclaimers
        }

insights = Insights()
safety_guard = SafetyGuard()