-- Create health_probe table for lightweight database health checks
-- Run this in Supabase SQL editor

CREATE TABLE IF NOT EXISTS health_probe (
    id INT PRIMARY KEY
);

INSERT INTO health_probe (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- Grant permissions for the anon key to read
GRANT SELECT ON health_probe TO anon;
GRANT SELECT ON health_probe TO authenticated;