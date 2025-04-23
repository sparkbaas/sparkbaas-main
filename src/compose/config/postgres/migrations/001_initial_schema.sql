-- Migration: 001_initial_schema.sql
-- Initial schema setup for SparkBaaS
-- Creates the basic tables and roles needed for the system

-- Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schema for API
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'Public API schema';

-- Create schema for auth
CREATE SCHEMA IF NOT EXISTS auth;
COMMENT ON SCHEMA auth IS 'Authentication and authorization schema';

-- Create schema for storage
CREATE SCHEMA IF NOT EXISTS storage;
COMMENT ON SCHEMA storage IS 'File storage schema';

-- Create schema for functions
CREATE SCHEMA IF NOT EXISTS functions;
COMMENT ON SCHEMA functions IS 'Serverless functions schema';

-- Create roles
DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
      CREATE ROLE anon;
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
      CREATE ROLE authenticator WITH LOGIN PASSWORD 'changeme';
      GRANT anon TO authenticator;
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
      CREATE ROLE authenticated;
      GRANT authenticated TO authenticator;
   END IF;
END
$do$;

-- Create version tracking table
CREATE TABLE IF NOT EXISTS public.version (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert current version
INSERT INTO public.version (version)
VALUES ('0.1.0')
ON CONFLICT DO NOTHING;

-- Create versioning table to track platform version
CREATE TABLE IF NOT EXISTS sparkbaas_versions (
  component TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert initial version information
INSERT INTO sparkbaas_versions (component, version)
VALUES 
  ('platform', '0.1.0'),
  ('database', '16.0'),
  ('auth', '22.0.0'),
  ('api', '3.0.0'),
  ('functions', '1.0.0')
ON CONFLICT (component) 
DO UPDATE SET 
  version = EXCLUDED.version,
  updated_at = NOW();

-- Create a function to register API keys
CREATE OR REPLACE FUNCTION api.register_api_key(
    p_name TEXT,
    p_role TEXT DEFAULT 'api_user'
) RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
    v_key_id TEXT;
BEGIN
    -- Generate a random API key
    v_key := encode(gen_random_bytes(32), 'hex');
    v_key_id := encode(gen_random_bytes(16), 'hex');
    
    -- Insert the API key into the api_keys table
    INSERT INTO auth.api_keys (id, name, key_hash, role)
    VALUES (
        v_key_id,
        p_name,
        crypt(v_key, gen_salt('bf')),
        p_role
    );
    
    -- Return the generated API key (this is the only time it will be visible)
    RETURN v_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create API keys table
CREATE TABLE IF NOT EXISTS auth.api_keys (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'api_user',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE
);

-- Create API key validation function
CREATE OR REPLACE FUNCTION auth.validate_api_key(p_api_key TEXT) 
RETURNS TABLE (
    id TEXT,
    role TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ak.id,
        ak.role
    FROM auth.api_keys ak
    WHERE ak.key_hash = crypt(p_api_key, ak.key_hash);
    
    -- Update last used timestamp
    UPDATE auth.api_keys
    SET last_used_at = NOW()
    WHERE key_hash = crypt(p_api_key, key_hash);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA api TO anon, authenticated;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA functions TO authenticated;

-- Create application table for items
CREATE TABLE IF NOT EXISTS api.items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_by TEXT REFERENCES api.users(id),
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create RLS policies for items
ALTER TABLE api.items ENABLE ROW LEVEL SECURITY;

-- Add update trigger
CREATE TRIGGER items_updated_at
BEFORE UPDATE ON api.items
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

-- Grant appropriate permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON api.items TO authenticated;
GRANT ALL ON api.items TO admin;

-- Create comments table
CREATE TABLE IF NOT EXISTS api.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES api.items(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_by TEXT REFERENCES api.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create RLS policies for comments
ALTER TABLE api.comments ENABLE ROW LEVEL SECURITY;

-- Add update trigger
CREATE TRIGGER comments_updated_at
BEFORE UPDATE ON api.comments
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

-- Grant appropriate permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON api.comments TO authenticated;
GRANT ALL ON api.comments TO admin;

-- Setup API tables
CREATE TABLE IF NOT EXISTS api.users (
   id SERIAL PRIMARY KEY,
   email TEXT UNIQUE NOT NULL,
   name TEXT,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
   last_login TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS api.projects (
   id SERIAL PRIMARY KEY,
   name TEXT NOT NULL,
   description TEXT,
   created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
   updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.user_projects (
   user_id INTEGER REFERENCES api.users(id) ON DELETE CASCADE,
   project_id INTEGER REFERENCES api.projects(id) ON DELETE CASCADE,
   role TEXT NOT NULL DEFAULT 'member',
   created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
   PRIMARY KEY (user_id, project_id)
);

-- Create row level security policies
ALTER TABLE api.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE api.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE api.user_projects ENABLE ROW LEVEL SECURITY;

-- Grant permissions
GRANT USAGE ON SCHEMA api TO anon, authenticated;
GRANT ALL ON api.users TO authenticated;
GRANT ALL ON api.projects TO authenticated;
GRANT ALL ON api.user_projects TO authenticated;
GRANT ALL ON api.users_id_seq TO authenticated;
GRANT ALL ON api.projects_id_seq TO authenticated;

-- Secure the tables with RLS policies
CREATE POLICY users_policy ON api.users TO authenticated
  USING (id = current_setting('request.jwt.claims', true)::json->>'user_id'::text);

CREATE POLICY projects_policy ON api.projects TO authenticated
  USING (id IN (
    SELECT project_id FROM api.user_projects 
    WHERE user_id = current_setting('request.jwt.claims', true)::json->>'user_id'::text
  ));

CREATE POLICY user_projects_policy ON api.user_projects TO authenticated
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'user_id'::text);

-- Create system functions
CREATE OR REPLACE FUNCTION api.current_user_id() RETURNS INTEGER AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'user_id', '')::INTEGER;
$$ LANGUAGE SQL STABLE;

-- Audit log table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id SERIAL PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    user_id INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    old_data JSONB,
    new_data JSONB
);

-- Function to log changes
CREATE OR REPLACE FUNCTION log_audit() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO public.audit_log(entity_type, entity_id, action, user_id, old_data)
        VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE', api.current_user_id(), row_to_json(OLD));
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO public.audit_log(entity_type, entity_id, action, user_id, old_data, new_data)
        VALUES (TG_TABLE_NAME, NEW.id::text, 'UPDATE', api.current_user_id(), row_to_json(OLD), row_to_json(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO public.audit_log(entity_type, entity_id, action, user_id, new_data)
        VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT', api.current_user_id(), row_to_json(NEW));
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers to tables
CREATE TRIGGER users_audit
AFTER INSERT OR UPDATE OR DELETE ON api.users
FOR EACH ROW EXECUTE PROCEDURE log_audit();

CREATE TRIGGER projects_audit
AFTER INSERT OR UPDATE OR DELETE ON api.projects
FOR EACH ROW EXECUTE PROCEDURE log_audit();

-- Add system metadata
COMMENT ON DATABASE postgres IS 'SparkBaaS main database';
COMMENT ON SCHEMA api IS 'API schema with public-facing tables';

-- Update metadata version
INSERT INTO api.sparkbaas_metadata (key, value)
VALUES ('schema_version', '0.1.0')
ON CONFLICT (key) DO UPDATE SET value = '0.1.0', updated_at = NOW();