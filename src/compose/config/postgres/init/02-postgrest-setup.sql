-- Create API schema
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'Public API Schema for application data';

-- Create security schema for authentication and authorization functions
CREATE SCHEMA IF NOT EXISTS security;
COMMENT ON SCHEMA security IS 'Security related functions and tables';

-- Create functions schema for PostgreSQL functions that can be called via API
CREATE SCHEMA IF NOT EXISTS functions;
COMMENT ON SCHEMA functions IS 'Custom PostgreSQL functions exposed via API';

-- Create storage schema for file metadata
CREATE SCHEMA IF NOT EXISTS storage;
COMMENT ON SCHEMA storage IS 'Storage metadata for files';

-- Create roles
-- Anonymous role (unauthenticated users)
CREATE ROLE anon NOLOGIN;
COMMENT ON ROLE anon IS 'Anonymous users (not authenticated)';

-- Authenticated role (logged in users)
CREATE ROLE authenticated NOLOGIN;
COMMENT ON ROLE authenticated IS 'Authenticated users';

-- Service role (internal services)
CREATE ROLE service NOLOGIN;
COMMENT ON ROLE service IS 'Service role for internal components';

-- Web authenticator role (used by PostgREST)
CREATE ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
COMMENT ON ROLE authenticator IS 'Role used by PostgREST to connect to the database';

-- Grant role memberships
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service TO authenticator;

-- Set up permissions
-- Anon permissions (public access)
GRANT USAGE ON SCHEMA api TO anon;
GRANT USAGE ON SCHEMA functions TO anon;

-- Authenticated permissions
GRANT USAGE ON SCHEMA api TO authenticated;
GRANT USAGE ON SCHEMA functions TO authenticated;
GRANT USAGE ON SCHEMA storage TO authenticated;

-- Service permissions
GRANT USAGE ON SCHEMA api TO service;
GRANT USAGE ON SCHEMA security TO service;
GRANT USAGE ON SCHEMA functions TO service;
GRANT USAGE ON SCHEMA storage TO service;
GRANT ALL ON SCHEMA api TO service;
GRANT ALL ON SCHEMA security TO service;

-- Create extension for generating UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create extension for full-text search
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create extension for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create sample users table in the api schema to demonstrate RLS
CREATE TABLE IF NOT EXISTS api.users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL CHECK (email ~* '^.+@.+\..+$'),
  name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE api.users IS 'Application users';

-- Enable RLS on users table
ALTER TABLE api.users ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY select_users ON api.users
  FOR SELECT
  USING (true);

CREATE POLICY insert_users ON api.users
  FOR INSERT
  WITH CHECK (auth.uid() = id);
  
CREATE POLICY update_users ON api.users
  FOR UPDATE
  USING (auth.uid() = id);
  
CREATE POLICY delete_users ON api.users
  FOR DELETE
  USING (auth.uid() = id);

-- Create function to get current authenticated user ID
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
BEGIN
  RETURN nullif(current_setting('request.jwt.claim.sub', true), '')::UUID;
EXCEPTION
  WHEN OTHERS THEN RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create function to check if user is authenticated
CREATE OR REPLACE FUNCTION auth.is_authenticated() RETURNS BOOLEAN AS $$
BEGIN
  RETURN auth.uid() IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

-- Create storage buckets table
CREATE TABLE IF NOT EXISTS storage.buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  public BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE storage.buckets IS 'Storage buckets for file management';

-- Create storage objects table
CREATE TABLE IF NOT EXISTS storage.objects (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bucket_id TEXT REFERENCES storage.buckets(id),
  name TEXT NOT NULL,
  owner UUID REFERENCES api.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  metadata JSONB,
  path TEXT,
  size INTEGER,
  mime_type TEXT
);
COMMENT ON TABLE storage.objects IS 'Storage objects (files)';

-- Enable RLS on storage tables
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for buckets
CREATE POLICY select_buckets ON storage.buckets
  FOR SELECT
  USING (public OR auth.is_authenticated());
  
-- Create RLS policies for objects
CREATE POLICY select_public_objects ON storage.objects
  FOR SELECT
  USING (
    bucket_id IN (SELECT id FROM storage.buckets WHERE public = true)
  );

CREATE POLICY select_own_objects ON storage.objects
  FOR SELECT
  USING (
    auth.uid() = owner
  );

CREATE POLICY insert_objects ON storage.objects
  FOR INSERT
  WITH CHECK (
    auth.uid() = owner
  );
  
CREATE POLICY update_own_objects ON storage.objects
  FOR UPDATE
  USING (
    auth.uid() = owner
  );
  
CREATE POLICY delete_own_objects ON storage.objects
  FOR DELETE
  USING (
    auth.uid() = owner
  );

-- Create default public bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('public', 'Public', true)
ON CONFLICT DO NOTHING;

-- Grant permissions on all tables
GRANT SELECT ON ALL TABLES IN SCHEMA api TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA api TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA api TO service;

GRANT SELECT ON storage.buckets TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.buckets TO authenticated;
GRANT ALL ON storage.buckets TO service;

GRANT SELECT ON storage.objects TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
GRANT ALL ON storage.objects TO service;

-- This will ensure permissions apply to new tables too
ALTER DEFAULT PRIVILEGES IN SCHEMA api GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA api GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA api GRANT ALL ON TABLES TO service;

-- PostgREST specific configuration
-- This script sets up the necessary configuration for PostgREST integration

-- Make sure we're connected to the postgres database
\c postgres;

-- Create jwt verification function
CREATE OR REPLACE FUNCTION api.verify_jwt() RETURNS void AS $$
DECLARE
  role_from_token text;
  user_id_from_token uuid;
BEGIN
  -- Get role and user_id from JWT
  role_from_token := current_setting('request.jwt.claim.role', true);
  user_id_from_token := (current_setting('request.jwt.claim.user_id', true))::uuid;

  -- Set role for this session
  IF role_from_token IS NOT NULL THEN
    -- Set role to value in JWT
    EXECUTE format('SET LOCAL ROLE %I', role_from_token);
  END IF;

  -- Set user_id as local setting
  PERFORM set_config('app.current_user_id', user_id_from_token::text, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create some utility functions

-- Function to check if user has a specific role
CREATE OR REPLACE FUNCTION api.has_role(role_name text) RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id::text = current_setting('request.jwt.claim.user_id', true)
    AND role = role_name
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate token is still valid
CREATE OR REPLACE FUNCTION api.check_token() RETURNS jsonb AS $$
BEGIN
  RETURN jsonb_build_object(
    'valid', true,
    'user_id', current_setting('request.jwt.claim.user_id', true),
    'role', current_setting('request.jwt.claim.role', true)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Permission grants
GRANT EXECUTE ON FUNCTION api.verify_jwt TO authenticator;
GRANT EXECUTE ON FUNCTION api.has_role TO authenticated;
GRANT EXECUTE ON FUNCTION api.check_token TO authenticated;

-- Create tables for functions management
CREATE TABLE IF NOT EXISTS public.functions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES public.users(id),
  updated_by UUID REFERENCES public.users(id)
);

CREATE TABLE IF NOT EXISTS public.function_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  function_id UUID NOT NULL REFERENCES public.functions(id),
  execution_time NUMERIC NOT NULL, -- in milliseconds
  success BOOLEAN NOT NULL,
  request JSONB,
  response JSONB,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID -- user who executed the function
);

-- Add API views for functions
CREATE OR REPLACE VIEW api.functions AS
  SELECT id, name, version, active, created_at, updated_at
  FROM public.functions;

CREATE OR REPLACE VIEW api.function_logs AS
  SELECT id, function_id, execution_time, success, error, created_at
  FROM public.function_logs;

-- Add RLS policies
ALTER TABLE public.functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.function_logs ENABLE ROW LEVEL SECURITY;

-- Function policies
CREATE POLICY functions_read ON public.functions
  FOR SELECT
  TO authenticated
  USING (active = true);

CREATE POLICY functions_admin ON public.functions
  FOR ALL
  TO admin
  USING (true);

-- Function logs policies
CREATE POLICY function_logs_view ON public.function_logs
  FOR SELECT
  TO authenticated
  USING (user_id::text = current_setting('request.jwt.claim.user_id', true));

CREATE POLICY function_logs_admin ON public.function_logs
  FOR SELECT
  TO admin
  USING (true);

-- Set table ownership
ALTER TABLE public.functions OWNER TO admin;
ALTER TABLE public.function_logs OWNER TO admin;

-- Permissions for functions
GRANT SELECT ON api.functions TO authenticated;
GRANT SELECT ON api.functions TO anon;