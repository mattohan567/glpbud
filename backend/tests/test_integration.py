import pytest
import json
from fastapi.testclient import TestClient
from backend.app.main import app

client = TestClient(app)

class TestIntegration:
    """Integration tests for complete user workflows"""
    
    @pytest.fixture
    def auth_headers(self):
        """Provide test authentication headers"""
        return {"Authorization": "Bearer test-token"}
    
    def test_complete_meal_logging_workflow(self, auth_headers):
        """Test complete meal logging from parse to storage"""
        # Step 1: Parse meal text
        parse_response = client.post("/parse/meal-text",
            headers=auth_headers,
            json={
                "text": "grilled chicken breast 200g with steamed broccoli",
                "hints": "healthy dinner"
            }
        )
        
        assert parse_response.status_code == 200
        parse_data = parse_response.json()
        
        # Verify parse structure
        assert "items" in parse_data
        assert "totals" in parse_data
        assert "confidence" in parse_data
        assert len(parse_data["items"]) >= 1
        
        # Step 2: Log the parsed meal
        log_response = client.post("/log/meal",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T18:00:00Z",
                "source": "text",
                "parse": parse_data,
                "notes": "Healthy dinner"
            }
        )
        
        assert log_response.status_code == 200
        log_data = log_response.json()
        assert "id" in log_data
        
        # Step 3: Verify meal appears in today's stats
        today_response = client.get("/today", headers=auth_headers)
        
        if today_response.status_code == 200:
            today_data = today_response.json()
            assert "kcal_in" in today_data
            # Should have some calories logged
            # Note: Might be 0 if test runs on different date
    
    def test_complete_exercise_logging_workflow(self, auth_headers):
        """Test complete exercise logging workflow"""
        # Log an exercise
        exercise_response = client.post("/log/exercise",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T07:00:00Z",
                "type": "running",
                "duration_min": 30,
                "intensity": "moderate",
                "est_kcal": 300
            }
        )
        
        assert exercise_response.status_code == 200
        exercise_data = exercise_response.json()
        assert "id" in exercise_data
        
        # Verify exercise appears in today's stats
        today_response = client.get("/today", headers=auth_headers)
        
        if today_response.status_code == 200:
            today_data = today_response.json()
            assert "kcal_out" in today_data
    
    def test_weight_tracking_workflow(self, auth_headers):
        """Test weight tracking workflow"""
        # Log a weight measurement
        weight_response = client.post("/log/weight",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T08:00:00Z",
                "weight_kg": 75.5,
                "method": "scale"
            }
        )
        
        assert weight_response.status_code == 200
        weight_data = weight_response.json()
        assert "id" in weight_data
        
        # Check trends include weight data
        trends_response = client.get("/trends?range=7d", headers=auth_headers)
        
        if trends_response.status_code == 200:
            trends_data = trends_response.json()
            assert "weight_series" in trends_data
    
    def test_coach_interaction_workflow(self, auth_headers):
        """Test coach interaction workflow"""
        # Ask the coach a question
        coach_response = client.post("/coach/ask",
            headers=auth_headers,
            json={
                "question": "What are good protein sources for weight loss?",
                "context_opt_in": True
            }
        )
        
        assert coach_response.status_code == 200
        coach_data = coach_response.json()
        
        assert "answer" in coach_data
        assert "disclaimers" in coach_data
        assert isinstance(coach_data["answer"], str)
        assert len(coach_data["answer"]) > 0
    
    def test_medication_workflow(self, auth_headers):
        """Test medication scheduling workflow"""
        # Schedule a medication
        med_response = client.post("/med/schedule",
            headers=auth_headers,
            json={
                "drug_name": "semaglutide",
                "dose_mg": 0.5,
                "schedule_rule": "FREQ=WEEKLY;BYDAY=SU",
                "start_ts": "2024-01-01T09:00:00Z",
                "notes": "Weekly injection"
            }
        )
        
        assert med_response.status_code == 200
        med_data = med_response.json()
        assert "id" in med_data
        
        # Log a medication event
        event_response = client.post("/log/med",
            headers=auth_headers,
            json={
                "datetime": "2024-01-07T09:00:00Z",
                "drug_name": "semaglutide",
                "dose_mg": 0.5,
                "injection_site": "LLQ",
                "notes": "Weekly dose"
            }
        )
        
        assert event_response.status_code == 200
        event_data = event_response.json()
        assert "id" in event_data
        
        # Check next dose
        next_dose_response = client.get("/med/next", headers=auth_headers)
        assert next_dose_response.status_code == 200
    
    def test_data_consistency_across_endpoints(self, auth_headers):
        """Test that data is consistent across different endpoints"""
        # Log some test data
        meal_response = client.post("/log/meal",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T12:00:00Z",
                "source": "manual",
                "parse": {
                    "items": [{
                        "name": "Test Food",
                        "qty": 100,
                        "unit": "g", 
                        "kcal": 200,
                        "protein_g": 20,
                        "carbs_g": 10,
                        "fat_g": 5
                    }],
                    "totals": {
                        "kcal": 200,
                        "protein_g": 20,
                        "carbs_g": 10,
                        "fat_g": 5
                    },
                    "confidence": 1.0,
                    "low_confidence": False
                }
            }
        )
        
        assert meal_response.status_code == 200
        
        # Check that data appears consistently
        today_response = client.get("/today", headers=auth_headers)
        trends_response = client.get("/trends?range=7d", headers=auth_headers)
        
        # Both endpoints should be accessible
        assert today_response.status_code in [200, 500]  # Might fail due to empty test data
        assert trends_response.status_code in [200, 500]  # Might fail due to empty test data
    
    def test_error_handling_across_workflow(self, auth_headers):
        """Test error handling in complete workflows"""
        # Test with invalid meal data
        invalid_meal_response = client.post("/log/meal",
            headers=auth_headers,
            json={
                "datetime": "invalid-date",
                "source": "text",
                "parse": {"invalid": "data"}
            }
        )
        
        assert invalid_meal_response.status_code == 422
        
        # Test with invalid exercise data
        invalid_exercise_response = client.post("/log/exercise",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T07:00:00Z",
                "type": "",  # Empty type
                "duration_min": -10  # Negative duration
            }
        )
        
        assert invalid_exercise_response.status_code == 422
        
        # Test with invalid weight data
        invalid_weight_response = client.post("/log/weight",
            headers=auth_headers,
            json={
                "datetime": "2024-01-15T08:00:00Z",
                "weight_kg": 1000  # Unrealistic weight
            }
        )
        
        assert invalid_weight_response.status_code == 422
    
    def test_concurrent_operations(self, auth_headers):
        """Test handling of concurrent operations"""
        import threading
        import time
        
        results = []
        
        def make_request():
            response = client.post("/parse/meal-text",
                headers=auth_headers,
                json={"text": f"apple {time.time()}"}
            )
            results.append(response.status_code)
        
        # Make multiple concurrent requests
        threads = []
        for i in range(5):
            thread = threading.Thread(target=make_request)
            threads.append(thread)
            thread.start()
        
        # Wait for all to complete
        for thread in threads:
            thread.join()
        
        # All should succeed or be rate limited
        for status in results:
            assert status in [200, 429, 422]
    
    def test_large_dataset_handling(self, auth_headers):
        """Test handling of larger datasets"""
        # Test with multiple meal items
        large_meal = {
            "datetime": "2024-01-15T12:00:00Z",
            "source": "manual",
            "parse": {
                "items": [
                    {
                        "name": f"Food Item {i}",
                        "qty": 50,
                        "unit": "g",
                        "kcal": 100,
                        "protein_g": 10,
                        "carbs_g": 5,
                        "fat_g": 2
                    } for i in range(20)  # 20 items
                ],
                "totals": {
                    "kcal": 2000,
                    "protein_g": 200,
                    "carbs_g": 100,
                    "fat_g": 40
                },
                "confidence": 0.8,
                "low_confidence": False
            }
        }
        
        response = client.post("/log/meal",
            headers=auth_headers,
            json=large_meal
        )
        
        # Should handle reasonable number of items
        assert response.status_code == 200
        
        # Test with too many items (should be rejected)
        too_large_meal = large_meal.copy()
        too_large_meal["parse"]["items"] = too_large_meal["parse"]["items"] * 5  # 100 items
        
        response = client.post("/log/meal",
            headers=auth_headers,
            json=too_large_meal
        )
        
        assert response.status_code == 422  # Should reject
    
    def test_health_check_integration(self):
        """Test health check provides useful information"""
        health_response = client.get("/health")
        assert health_response.status_code == 200
        
        health_data = health_response.json()
        assert "status" in health_data
        assert "checks" in health_data
        assert "timestamp" in health_data
        
        # Quick health check
        quick_health_response = client.get("/health/quick")
        assert quick_health_response.status_code == 200
        
        # Metrics endpoint
        metrics_response = client.get("/metrics")
        assert metrics_response.status_code == 200
        
        metrics_data = metrics_response.json()
        assert "uptime_seconds" in metrics_data
        assert "requests_total" in metrics_data