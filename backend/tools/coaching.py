from typing import Dict, Any, List
import json
try:
    from app.llm import claude_call
except ImportError:
    from backend.app.llm import claude_call

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
        Use Claude for sophisticated safety checking and disclaimer generation.
        """
        system_prompt = """You are a medical safety evaluator for a GLP-1 weight management app.
        Analyze the user's question for medical safety concerns.
        Return ONLY valid JSON in this exact format with no additional text:
        {
          "allow": true or false,
          "risk_level": "low" or "medium" or "high",
          "disclaimers": [list of relevant disclaimers if needed],
          "reasoning": "brief explanation"
        }
        
        Rules:
        1. BLOCK (allow=false) if asking for:
           - Specific medication dosing advice
           - Whether to start/stop medications
           - Diagnosis of symptoms
           - Emergency medical situations
        
        2. ADD DISCLAIMERS for:
           - General GLP-1 information ("Consult your healthcare provider")
           - Side effects discussion ("This is for information only")
           - Very low calorie diets (<1200 cal)
           - Exercise with medical conditions
        
        3. ALLOW general:
           - Nutrition advice
           - Exercise recommendations
           - Weight loss tips
           - Lifestyle coaching
        """
        
        user_message = f"User question: {message}"
        
        try:
            # Call Claude for safety analysis
            response = claude_call(
                messages=[{"role": "user", "content": user_message}],
                system=system_prompt,
                model="claude-3-5-haiku-20241022",
                metadata={"tool": "safety_guard", "message": message[:100]}
            )
            
            # Extract JSON from response
            response_text = response.content[0].text if response.content else "{}"
            
            try:
                if "```json" in response_text:
                    response_text = response_text.split("```json")[1].split("```")[0]
                elif "```" in response_text:
                    response_text = response_text.split("```")[1].split("```")[0]
                    
                data = json.loads(response_text)
                
                return {
                    "allow": data.get("allow", True),
                    "redactions": [],
                    "disclaimers": data.get("disclaimers", [])
                }
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Failed to parse Claude safety response: {e}")
                return self._fallback_check(message)
                
        except Exception as e:
            print(f"Claude API call failed for safety check: {e}")
            return self._fallback_check(message)
    
    def _fallback_check(self, message: str) -> Dict[str, Any]:
        """Fallback safety check when Claude is unavailable"""
        medical_keywords = [
            "dose", "medication", "side effect", "nausea", "vomiting",
            "heart", "blood pressure", "diabetes", "pregnant", "surgery",
            "ozempic", "wegovy", "mounjaro", "zepbound", "semaglutide", "tirzepatide"
        ]
        
        disclaimers = []
        allow = True
        message_lower = message.lower()
        
        # Check for medical keywords
        for keyword in medical_keywords:
            if keyword in message_lower:
                disclaimers.append(
                    "This information is for educational purposes only. "
                    "Always consult your healthcare provider for medical advice."
                )
                break
        
        # Check for extreme calorie targets
        if any(cal in message for cal in ["1200", "1000", "800", "500"]):
            disclaimers.append(
                "Very low calorie diets should only be followed under medical supervision."
            )
        
        # Block direct medical prescriptions
        if any(phrase in message_lower for phrase in ["should i take", "can i stop", "change my dose", "increase dose", "decrease dose"]):
            allow = False
            disclaimers.append(
                "I cannot provide specific medical advice. Please consult your healthcare provider."
            )
        
        return {
            "allow": allow,
            "redactions": [],
            "disclaimers": disclaimers
        }

insights = Insights()
safety_guard = SafetyGuard()