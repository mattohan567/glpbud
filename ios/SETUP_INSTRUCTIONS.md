# iOS App Setup Instructions

## Camera Permissions

To enable photo capture for meal logging, you need to add the following keys to your Info.plist in Xcode:

1. Open the project in Xcode
2. Select the GLP1Coach target
3. Go to the Info tab
4. Add these keys:

### Camera Usage
- **Key**: Privacy - Camera Usage Description
- **Value**: "GLP1 Coach needs camera access to take photos of your meals for nutritional analysis"

### Photo Library Usage
- **Key**: Privacy - Photo Library Usage Description  
- **Value**: "GLP1 Coach needs photo library access to select meal photos for nutritional analysis"

## Build and Run

1. Clean Build Folder: `Cmd+Shift+K`
2. Build and Run: `Cmd+R`

## Features Now Available

✅ **Meal Logging**
- Text input with Claude nutrition parsing
- Photo capture with Claude Vision analysis
- Accurate calorie and macro tracking

✅ **Exercise Tracking**
- Claude-powered exercise recognition
- Accurate MET-based calorie calculations
- Intensity detection

✅ **AI Coach**
- Personalized responses with optional context
- Medical safety disclaimers
- Privacy settings

✅ **Data Visualization**
- Weight trends
- Calorie intake/burn charts
- Activity summaries

## Backend Requirements

Make sure the backend is running:
```bash
cd backend
source /opt/anaconda3/bin/activate glpbud
uvicorn app.main:app --port 8000 --reload
```

## Testing

1. Log in with test@example.com / test123456
2. Try taking a photo of food to test Claude Vision
3. Ask the coach a nutrition question
4. Log an exercise to see calorie estimation