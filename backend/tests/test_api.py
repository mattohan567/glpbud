import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
from app.main import app
from app.schemas import MealParse, MealItem, MacroTotals

client = TestClient(app)

@pytest.fixture
def mock_auth():
    """Mock authentication for tests."""
    with patch('app.main.get_current_user') as mock:
        mock.return_value = MagicMock(id="test-user-id", email="test@example.com")
        yield mock

@pytest.fixture
def auth_headers():
    """Provide test authentication headers."""
    return {"Authorization": "Bearer test-token"}

def test_health_endpoint():
    """Test health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data

@patch('app.main.text_nutrition.parse')
def test_parse_meal_text(mock_parse, mock_auth, auth_headers):
    """Test meal text parsing endpoint."""
    mock_parse.return_value = MealParse(
        items=[
            MealItem(
                name="chicken breast",
                qty=150,
                unit="g",
                kcal=248,
                protein_g=46.5,
                carbs_g=0,
                fat_g=5.4
            )
        ],
        totals=MacroTotals(kcal=248, protein_g=46.5, carbs_g=0, fat_g=5.4),
        confidence=0.9,
        low_confidence=False
    )
    
    response = client.post(
        "/parse/meal-text",
        json={"text": "grilled chicken breast"},
        headers=auth_headers
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["confidence"] == 0.9
    assert data["totals"]["kcal"] == 248
    assert len(data["items"]) == 1

@patch('app.main.vision_nutrition.parse')
def test_parse_meal_image(mock_parse, mock_auth, auth_headers):
    """Test meal image parsing endpoint."""
    mock_parse.return_value = MealParse(
        items=[
            MealItem(
                name="salad",
                qty=200,
                unit="g",
                kcal=50,
                protein_g=2,
                carbs_g=10,
                fat_g=0.5
            )
        ],
        totals=MacroTotals(kcal=50, protein_g=2, carbs_g=10, fat_g=0.5),
        confidence=0.75,
        low_confidence=False
    )
    
    response = client.post(
        "/parse/meal-image",
        json={"image_url": "https://example.com/image.jpg"},
        headers=auth_headers
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["confidence"] == 0.75

@patch('app.main.supabase')
def test_log_meal(mock_supabase, mock_auth, auth_headers):
    """Test meal logging endpoint."""
    mock_supabase.table.return_value.insert.return_value.execute.return_value = MagicMock()
    
    meal_data = {
        "datetime": "2024-01-15T12:00:00",
        "source": "text",
        "parse": {
            "items": [
                {
                    "name": "test food",
                    "qty": 100,
                    "unit": "g",
                    "kcal": 200,
                    "protein_g": 20,
                    "carbs_g": 20,
                    "fat_g": 10
                }
            ],
            "totals": {
                "kcal": 200,
                "protein_g": 20,
                "carbs_g": 20,
                "fat_g": 10
            },
            "confidence": 0.8,
            "low_confidence": False
        },
        "notes": "Test meal"
    }
    
    response = client.post(
        "/log/meal",
        json=meal_data,
        headers=auth_headers
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] == True
    assert "id" in data

@patch('app.main.supabase')
def test_log_exercise(mock_supabase, mock_auth, auth_headers):
    """Test exercise logging endpoint."""
    mock_supabase.table.return_value.insert.return_value.execute.return_value = MagicMock()
    
    exercise_data = {
        "datetime": "2024-01-15T08:00:00",
        "type": "running",
        "duration_min": 30,
        "intensity": "moderate",
        "est_kcal": 300
    }
    
    response = client.post(
        "/log/exercise",
        json=exercise_data,
        headers=auth_headers
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] == True

@patch('app.main.supabase')
def test_get_today(mock_supabase, mock_auth, auth_headers):
    """Test today stats endpoint."""
    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.single.return_value.execute.return_value.data = {
        "kcal_in": 1500,
        "kcal_out": 300,
        "protein_g": 100,
        "carbs_g": 150,
        "fat_g": 50
    }
    
    mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value.data = []
    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.single.return_value.execute.return_value.data = None
    
    response = client.get("/today", headers=auth_headers)
    
    assert response.status_code == 200
    data = response.json()
    assert "kcal_in" in data
    assert "kcal_out" in data
    assert "protein_g" in data

@patch('app.main.safety_guard.check')
@patch('app.main.claude_call')
def test_coach_ask(mock_claude, mock_safety, mock_auth, auth_headers):
    """Test coach ask endpoint."""
    mock_safety.return_value = {
        "allow": True,
        "disclaimers": ["This is for educational purposes only."]
    }
    
    mock_response = MagicMock()
    mock_response.content = [MagicMock(text="Protein helps with satiety and muscle preservation.")]
    mock_claude.return_value = mock_response
    
    response = client.post(
        "/coach/ask",
        json={"question": "Why is protein important?"},
        headers=auth_headers
    )
    
    assert response.status_code == 200
    data = response.json()
    assert "answer" in data
    assert len(data["disclaimers"]) > 0

def test_unauthorized_request():
    """Test that requests without auth fail."""
    response = client.get("/today")
    assert response.status_code == 401