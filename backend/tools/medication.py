from typing import Dict, Any, List
from datetime import datetime, timedelta
from dateutil import rrule

class GLP1Adherence:
    def get_next_dose(self, user_ctx: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculate next GLP-1 dose timestamp and provide adherence suggestions.
        TODO: Integrate with actual medication schedule from database
        """
        # Dummy implementation - replace with actual schedule calculation
        next_due = datetime.now() + timedelta(days=7)
        
        suggestions = [
            "Set a reminder on your phone for your next dose",
            "Keep your medication refrigerated between 36-46°F",
            "Rotate injection sites to prevent irritation"
        ]
        
        cautions = [
            "Never change your dose without consulting your healthcare provider",
            "If you miss a dose by more than 5 days, contact your doctor"
        ]
        
        return {
            "next_due": next_due.isoformat(),
            "suggestions": suggestions,
            "cautions": cautions
        }
    
    def parse_schedule(self, schedule_rule: str, start_ts: datetime) -> List[datetime]:
        """
        Parse RFC5545 RRULE and generate next doses.
        """
        try:
            rule = rrule.rrulestr(schedule_rule, dtstart=start_ts)
            next_doses = list(rule[:10])  # Get next 10 doses
            return next_doses
        except Exception:
            # Fallback to weekly
            return [start_ts + timedelta(weeks=i) for i in range(10)]

glp1_adherence = GLP1Adherence()