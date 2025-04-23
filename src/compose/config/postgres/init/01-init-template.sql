-- SparkBaaS Initial Database Setup
-- This file is a template that gets processed with environment variable substitution

-- Create basic roles for authentication
CREATE ROLE anon NOLOGIN NOINHERIT;
COMMENT ON ROLE anon IS 'Anonymous role for public access';

CREATE ROLE authenticated NOLOGIN NOINHERIT;
COMMENT ON ROLE authenticated IS 'Authenticated users role';

CREATE ROLE admin NOLOGIN NOINHERIT;
COMMENT ON ROLE admin IS 'Administrator role with full access';

-- Grant privileges to the authenticator role
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT admin TO authenticator WITH ADMIN OPTION;

-- Create API schema
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'Public API schema';

-- Create auth schema
CREATE SCHEMA IF NOT EXISTS auth;
COMMENT ON SCHEMA auth IS 'Authentication and authorization schema';

-- Create storage schema
CREATE SCHEMA IF NOT EXISTS storage;
COMMENT ON SCHEMA storage IS 'File storage schema';

-- Create functions schema
CREATE SCHEMA IF NOT EXISTS functions;
COMMENT ON SCHEMA functions IS 'Serverless functions schema';

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT USAGE ON SCHEMA api TO anon, authenticated;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA functions TO authenticated;

-- Create updated_at timestamp trigger function
CREATE OR REPLACE FUNCTION api.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create users table
CREATE TABLE IF NOT EXISTS api.users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'user',
  metadata JSONB DEFAULT '{}'::jsonb,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable row level security
ALTER TABLE api.users ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY users_select_own ON api.users FOR SELECT
  USING (id = current_user_id() OR role = 'admin');

CREATE POLICY users_update_own ON api.users FOR UPDATE
  USING (id = current_user_id() OR role = 'admin')
  WITH CHECK (id = current_user_id() OR role = 'admin');

-- Create update trigger
CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON api.users
  FOR EACH ROW
  EXECUTE FUNCTION api.update_timestamp();

-- Grant access to the users table
GRANT SELECT ON api.users TO authenticated;
GRANT UPDATE (email, display_name, avatar_url, metadata) ON api.users TO authenticated;
GRANT ALL ON api.users TO admin;

-- Create metadata table
CREATE TABLE IF NOT EXISTS api.sparkbaas_metadata (
  key TEXT PRIMARY KEY,
  value TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insert version information
INSERT INTO api.sparkbaas_metadata (key, value)
VALUES ('version', '0.1.0')
ON CONFLICT (key) DO UPDATE SET value = '0.1.0';

-- Create current_user_id() function to use in RLS policies
CREATE OR REPLACE FUNCTION current_user_id() 
RETURNS TEXT AS $$
BEGIN
  RETURN current_setting('request.jwt.claims', TRUE)::json->>'sub';
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create utility functions
CREATE OR REPLACE FUNCTION api.is_admin() 
RETURNS BOOLEAN AS $$
BEGIN
  RETURN (current_setting('request.jwt.claims', TRUE)::json->>'role' = 'admin');
EXCEPTION
  WHEN OTHERS THEN
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create audit log table
CREATE TABLE IF NOT EXISTS auth.audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT,
  event_type TEXT NOT NULL,
  resource TEXT,
  data JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create audit log function
CREATE OR REPLACE FUNCTION auth.create_audit_log(
  p_user_id TEXT,
  p_event_type TEXT,
  p_resource TEXT,
  p_data JSONB DEFAULT NULL,
  p_ip_address TEXT DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  INSERT INTO auth.audit_log (user_id, event_type, resource, data, ip_address, user_agent)
  VALUES (p_user_id, p_event_type, p_resource, p_data, p_ip_address, p_user_agent);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Log initialization
SELECT auth.create_audit_log(
  'system', 
  'system.init',
  'database',
  jsonb_build_object('version', '0.1.0', 'initialized_at', now()::text)
);

-- Create storage.buckets table
CREATE TABLE IF NOT EXISTS storage.buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  public BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create storage.objects table
CREATE TABLE IF NOT EXISTS storage.objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id TEXT NOT NULL REFERENCES storage.buckets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  owner TEXT REFERENCES api.users(id),
  size BIGINT NOT NULL,
  mime_type TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (bucket_id, name)
);

-- Enable row level security
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Create bucket for user uploads
INSERT INTO storage.buckets (id, name, public)
VALUES ('user-uploads', 'User Uploads', false)
ON CONFLICT (id) DO NOTHING;

-- Create public bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('public', 'Public Files', true)
ON CONFLICT (id) DO NOTHING;

-- Add RLS policies
CREATE POLICY buckets_select_public ON storage.buckets FOR SELECT
  USING (public = true OR EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = buckets.id
    AND owner = current_user_id()
  ));

CREATE POLICY objects_select_public ON storage.objects FOR SELECT
  USING (
    (SELECT public FROM storage.buckets WHERE id = bucket_id) 
    OR owner = current_user_id() 
    OR api.is_admin()
  );

CREATE POLICY objects_insert_own ON storage.objects FOR INSERT
  WITH CHECK (owner = current_user_id() OR api.is_admin());

CREATE POLICY objects_update_own ON storage.objects FOR UPDATE
  USING (owner = current_user_id() OR api.is_admin())
  WITH CHECK (owner = current_user_id() OR api.is_admin());

CREATE POLICY objects_delete_own ON storage.objects FOR DELETE
  USING (owner = current_user_id() OR api.is_admin());

-- Create update triggers
CREATE TRIGGER buckets_updated_at
  BEFORE UPDATE ON storage.buckets
  FOR EACH ROW
  EXECUTE FUNCTION api.update_timestamp();

CREATE TRIGGER objects_updated_at
  BEFORE UPDATE ON storage.objects
  FOR EACH ROW
  EXECUTE FUNCTION api.update_timestamp();

-- Grant appropriate permissions
GRANT SELECT ON storage.buckets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets, storage.objects TO admin;