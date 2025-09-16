-- GLP-1 Coach Database Schema for Supabase
-- This schema defines all tables, constraints, and indexes for the application
-- 
-- DEPLOYMENT INSTRUCTIONS:
-- 1. Open your Supabase project dashboard
-- 2. Go to SQL Editor
-- 3. Run this entire script
-- 4. Verify all tables and policies are created successfully

-- Supabase already has UUID extension enabled
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- Already enabled in Supabase

-- Supabase has RLS enabled by default
-- Row Level Security is enabled on all auth-related tables

-- Users table (extends Supabase auth.users)
-- Note: Supabase automatically creates auth.users table
-- This table stores additional profile information
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid() REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Profile information
    height_cm INTEGER CHECK (height_cm > 0 AND height_cm < 300),
    sex VARCHAR(10) CHECK (sex IN ('male', 'female', 'other')),
    birth_date DATE,
    activity_level VARCHAR(20) CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'very_active')),
    timezone VARCHAR(50) DEFAULT 'UTC',
    
    -- Preferences
    weight_unit VARCHAR(10) DEFAULT 'kg' CHECK (weight_unit IN ('kg', 'lbs')),
    height_unit VARCHAR(10) DEFAULT 'cm' CHECK (height_unit IN ('cm', 'ft')),
    calorie_target INTEGER CHECK (calorie_target > 0 AND calorie_target < 10000),
    protein_target_g INTEGER CHECK (protein_target_g >= 0 AND protein_target_g < 1000)
);

-- Add indexes for users table
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Meals table
CREATE TABLE IF NOT EXISTS public.meals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Meal data
    source VARCHAR(20) NOT NULL CHECK (source IN ('image', 'text', 'manual')),
    items JSONB NOT NULL CHECK (jsonb_array_length(items) > 0),
    totals JSONB NOT NULL,
    confidence DECIMAL(3,2) CHECK (confidence >= 0 AND confidence <= 1),
    low_confidence BOOLEAN DEFAULT FALSE,
    
    -- Optional fields
    notes TEXT,
    image_url TEXT,
    text_raw TEXT
);

-- Add indexes for meals table
CREATE INDEX IF NOT EXISTS idx_meals_user_id ON meals(user_id);
CREATE INDEX IF NOT EXISTS idx_meals_ts ON meals(ts);
CREATE INDEX IF NOT EXISTS idx_meals_user_ts ON meals(user_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_meals_source ON meals(source);
CREATE INDEX IF NOT EXISTS idx_meals_confidence ON meals(confidence);

-- Exercises table
CREATE TABLE IF NOT EXISTS public.exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Exercise data
    type VARCHAR(200) NOT NULL,
    duration_min DECIMAL(8,2) NOT NULL CHECK (duration_min > 0 AND duration_min <= 1440),
    intensity VARCHAR(20) CHECK (intensity IN ('low', 'moderate', 'high')),
    est_kcal INTEGER CHECK (est_kcal >= 0 AND est_kcal < 50000),
    
    -- Optional fields
    source_text TEXT,
    notes TEXT
);

-- Add indexes for exercises table
CREATE INDEX IF NOT EXISTS idx_exercises_user_id ON exercises(user_id);
CREATE INDEX IF NOT EXISTS idx_exercises_ts ON exercises(ts);
CREATE INDEX IF NOT EXISTS idx_exercises_user_ts ON exercises(user_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_type ON exercises(type);

-- Weights table
CREATE TABLE IF NOT EXISTS public.weights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Weight data
    weight_kg DECIMAL(5,2) NOT NULL CHECK (weight_kg > 0 AND weight_kg < 1000),
    method VARCHAR(20) DEFAULT 'manual' CHECK (method IN ('scale', 'manual', 'healthkit', 'estimated'))
);

-- Add indexes for weights table
CREATE INDEX IF NOT EXISTS idx_weights_user_id ON weights(user_id);
CREATE INDEX IF NOT EXISTS idx_weights_ts ON weights(ts);
CREATE INDEX IF NOT EXISTS idx_weights_user_ts ON weights(user_id, ts DESC);

-- Medications table (renamed from med_schedules for consistency)
CREATE TABLE IF NOT EXISTS public.medications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Medication info
    drug_name VARCHAR(100) NOT NULL,
    dose_mg DECIMAL(8,2) NOT NULL CHECK (dose_mg > 0 AND dose_mg <= 100),
    schedule_rule TEXT NOT NULL, -- RFC5545 RRULE format
    start_ts TIMESTAMPTZ NOT NULL,
    end_ts TIMESTAMPTZ, -- Optional end date
    active BOOLEAN DEFAULT TRUE,
    
    -- Optional fields
    notes TEXT,
    prescriber VARCHAR(200),
    pharmacy VARCHAR(200)
);

-- Add indexes for medications table
CREATE INDEX IF NOT EXISTS idx_medications_user_id ON medications(user_id);
CREATE INDEX IF NOT EXISTS idx_medications_active ON medications(active);
CREATE INDEX IF NOT EXISTS idx_medications_drug_name ON medications(drug_name);

-- Medication events table (for logging actual doses taken)
CREATE TABLE IF NOT EXISTS public.med_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    medication_id UUID REFERENCES public.medications(id) ON DELETE SET NULL,
    ts TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Event data
    drug_name VARCHAR(100) NOT NULL,
    dose_mg DECIMAL(8,2) NOT NULL CHECK (dose_mg > 0 AND dose_mg <= 100),
    injection_site VARCHAR(20) CHECK (injection_site IN ('LLQ', 'RLQ', 'LUQ', 'RUQ', 'thigh_left', 'thigh_right', 'arm_left', 'arm_right')),
    
    -- Optional fields
    side_effects TEXT[],
    notes TEXT,
    missed BOOLEAN DEFAULT FALSE,
    late_by_hours INTEGER CHECK (late_by_hours >= 0 AND late_by_hours <= 168) -- Max 1 week late
);

-- Add indexes for med_events table
CREATE INDEX IF NOT EXISTS idx_med_events_user_id ON med_events(user_id);
CREATE INDEX IF NOT EXISTS idx_med_events_ts ON med_events(ts);
CREATE INDEX IF NOT EXISTS idx_med_events_medication_id ON med_events(medication_id);
CREATE INDEX IF NOT EXISTS idx_med_events_drug_name ON med_events(drug_name);

-- Tool runs table (for observability)
CREATE TABLE IF NOT EXISTS public.tool_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Tool execution data
    tool_name VARCHAR(100) NOT NULL,
    input JSONB,
    output JSONB,
    model VARCHAR(100),
    latency_ms INTEGER CHECK (latency_ms >= 0),
    cost_usd DECIMAL(10,6) CHECK (cost_usd >= 0),
    success BOOLEAN NOT NULL,
    error TEXT,
    
    -- Request context
    request_id UUID,
    endpoint VARCHAR(200)
);

-- Add indexes for tool_runs table
CREATE INDEX IF NOT EXISTS idx_tool_runs_user_id ON tool_runs(user_id);
CREATE INDEX IF NOT EXISTS idx_tool_runs_created_at ON tool_runs(created_at);
CREATE INDEX IF NOT EXISTS idx_tool_runs_tool_name ON tool_runs(tool_name);
CREATE INDEX IF NOT EXISTS idx_tool_runs_success ON tool_runs(success);
CREATE INDEX IF NOT EXISTS idx_tool_runs_model ON tool_runs(model);

-- Event bus table (for analytics and debugging)
CREATE TABLE IF NOT EXISTS public.event_bus (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Event data
    type VARCHAR(100) NOT NULL,
    payload JSONB,
    session_id UUID,
    request_id UUID
);

-- Add indexes for event_bus table
CREATE INDEX IF NOT EXISTS idx_event_bus_user_id ON event_bus(user_id);
CREATE INDEX IF NOT EXISTS idx_event_bus_created_at ON event_bus(created_at);
CREATE INDEX IF NOT EXISTS idx_event_bus_type ON event_bus(type);
CREATE INDEX IF NOT EXISTS idx_event_bus_session_id ON event_bus(session_id);

-- Analytics daily table (for pre-computed daily stats)
CREATE TABLE IF NOT EXISTS public.analytics_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Daily aggregates
    kcal_in INTEGER DEFAULT 0 CHECK (kcal_in >= 0),
    kcal_out INTEGER DEFAULT 0 CHECK (kcal_out >= 0),
    protein_g DECIMAL(8,2) DEFAULT 0 CHECK (protein_g >= 0),
    carbs_g DECIMAL(8,2) DEFAULT 0 CHECK (carbs_g >= 0),
    fat_g DECIMAL(8,2) DEFAULT 0 CHECK (fat_g >= 0),
    fiber_g DECIMAL(8,2) DEFAULT 0 CHECK (fiber_g >= 0),
    
    -- Counts
    meals_logged INTEGER DEFAULT 0 CHECK (meals_logged >= 0),
    exercises_logged INTEGER DEFAULT 0 CHECK (exercises_logged >= 0),
    
    -- Weight (latest for the day)
    weight_kg DECIMAL(5,2) CHECK (weight_kg > 0 AND weight_kg < 1000),
    
    UNIQUE(user_id, day)
);

-- Add indexes for analytics_daily table
CREATE INDEX IF NOT EXISTS idx_analytics_daily_user_id ON analytics_daily(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_daily_day ON analytics_daily(day);
CREATE INDEX IF NOT EXISTS idx_analytics_daily_user_day ON analytics_daily(user_id, day DESC);

-- Add triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers to relevant tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_meals_updated_at BEFORE UPDATE ON meals FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_exercises_updated_at BEFORE UPDATE ON exercises FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_weights_updated_at BEFORE UPDATE ON weights FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_medications_updated_at BEFORE UPDATE ON medications FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_analytics_daily_updated_at BEFORE UPDATE ON analytics_daily FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Row Level Security Policies for Supabase
-- Supabase RLS uses auth.uid() to get the current user's ID

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.med_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_daily ENABLE ROW LEVEL SECURITY;

-- Policies: Users can only access their own data
-- Using Supabase's auth.uid() function
CREATE POLICY "Users can view own profile" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can manage own meals" ON public.meals FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own exercises" ON public.exercises FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own weights" ON public.weights FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own medications" ON public.medications FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own med events" ON public.med_events FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own analytics" ON public.analytics_daily FOR ALL USING (auth.uid() = user_id);

-- Service role policies (for backend API operations)
-- The service role can access all data for backend operations
CREATE POLICY "Service role has full access to users" ON public.users FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to meals" ON public.meals FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to exercises" ON public.exercises FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to weights" ON public.weights FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to medications" ON public.medications FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to med events" ON public.med_events FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to tool runs" ON public.tool_runs FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to event bus" ON public.event_bus FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role has full access to analytics" ON public.analytics_daily FOR ALL USING (auth.role() = 'service_role');

-- Functions for data aggregation and cleanup

-- Function to update daily analytics
CREATE OR REPLACE FUNCTION update_daily_analytics(target_user_id UUID, target_date DATE)
RETURNS VOID AS $$
DECLARE
    day_start TIMESTAMPTZ;
    day_end TIMESTAMPTZ;
    daily_stats RECORD;
BEGIN
    -- Calculate day boundaries
    day_start := target_date::TIMESTAMPTZ;
    day_end := (target_date + INTERVAL '1 day')::TIMESTAMPTZ;
    
    -- Calculate daily aggregates
    SELECT 
        COALESCE(SUM((totals->>'kcal')::INTEGER), 0) as kcal_in,
        COALESCE(SUM((totals->>'protein_g')::DECIMAL), 0) as protein_g,
        COALESCE(SUM((totals->>'carbs_g')::DECIMAL), 0) as carbs_g,
        COALESCE(SUM((totals->>'fat_g')::DECIMAL), 0) as fat_g,
        COUNT(*) as meals_logged
    INTO daily_stats
    FROM meals 
    WHERE user_id = target_user_id 
    AND ts >= day_start 
    AND ts < day_end;
    
    -- Get exercise totals
    SELECT 
        COALESCE(SUM(est_kcal), 0) as kcal_out,
        COUNT(*) as exercises_logged
    INTO daily_stats.kcal_out, daily_stats.exercises_logged
    FROM exercises 
    WHERE user_id = target_user_id 
    AND ts >= day_start 
    AND ts < day_end;
    
    -- Get latest weight for the day
    SELECT weight_kg INTO daily_stats.weight_kg
    FROM weights 
    WHERE user_id = target_user_id 
    AND ts >= day_start 
    AND ts < day_end
    ORDER BY ts DESC 
    LIMIT 1;
    
    -- Upsert daily analytics
    INSERT INTO analytics_daily (
        user_id, day, kcal_in, kcal_out, protein_g, carbs_g, fat_g,
        meals_logged, exercises_logged, weight_kg
    ) VALUES (
        target_user_id, target_date, daily_stats.kcal_in, daily_stats.kcal_out,
        daily_stats.protein_g, daily_stats.carbs_g, daily_stats.fat_g,
        daily_stats.meals_logged, daily_stats.exercises_logged, daily_stats.weight_kg
    )
    ON CONFLICT (user_id, day) DO UPDATE SET
        kcal_in = EXCLUDED.kcal_in,
        kcal_out = EXCLUDED.kcal_out,
        protein_g = EXCLUDED.protein_g,
        carbs_g = EXCLUDED.carbs_g,
        fat_g = EXCLUDED.fat_g,
        meals_logged = EXCLUDED.meals_logged,
        exercises_logged = EXCLUDED.exercises_logged,
        weight_kg = EXCLUDED.weight_kg,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old data
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INTEGER DEFAULT 365)
RETURNS INTEGER AS $$
DECLARE
    cutoff_date TIMESTAMPTZ;
    deleted_count INTEGER := 0;
BEGIN
    cutoff_date := NOW() - INTERVAL '1 day' * days_to_keep;
    
    -- Clean up old tool runs (keep 90 days)
    DELETE FROM tool_runs WHERE created_at < (NOW() - INTERVAL '90 days');
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Clean up old event bus entries (keep 180 days)
    DELETE FROM event_bus WHERE created_at < (NOW() - INTERVAL '180 days');
    GET DIAGNOSTICS deleted_count = deleted_count + ROW_COUNT;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;