-- Initialize SparkBaaS PostgreSQL Database
-- This script sets up the necessary roles, users, and permissions

-- Create Keycloak User and Database
CREATE USER keycloak WITH PASSWORD '${KEYCLOAK_DB_PASSWORD}';
CREATE DATABASE keycloak OWNER keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;

-- Create Kong User and Database
CREATE USER kong WITH PASSWORD '${KONG_PG_PASSWORD}';
CREATE DATABASE kong OWNER kong;
GRANT ALL PRIVILEGES ON DATABASE kong TO kong;

-- Connect to the postgres database to set up PostgREST authentication
\c postgres;

-- Create Schema for API
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'Schema for SparkBaaS API';

-- Create Schema for application data
CREATE SCHEMA IF NOT EXISTS app;
COMMENT ON SCHEMA app IS 'Schema for application data';

-- Create authenticator role for PostgREST
CREATE ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}' NOINHERIT;
COMMENT ON ROLE authenticator IS 'Role used by PostgREST to connect to the database';

-- Create anonymous role (used for unauthenticated requests)
CREATE ROLE anon;
COMMENT ON ROLE anon IS 'Role for unauthenticated users (public access)';

-- Create authenticated role (used for authenticated requests)
CREATE ROLE authenticated;
COMMENT ON ROLE authenticated IS 'Role for authenticated users';

-- Create admin role
CREATE ROLE admin;
COMMENT ON ROLE admin IS 'Role for admin users with elevated privileges';

-- Grant roles to authenticator
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT admin TO authenticator;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT USAGE ON SCHEMA api TO anon, authenticated;
GRANT USAGE, CREATE ON SCHEMA app TO authenticated, admin;

-- Grant admin full access to all schemas
GRANT ALL ON SCHEMA public, api, app TO admin;

-- Create basic user management tables
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  PRIMARY KEY (user_id, role)
);

-- Create API views
CREATE OR REPLACE VIEW api.users AS
  SELECT id, email, name, created_at, updated_at 
  FROM public.users;

CREATE OR REPLACE VIEW api.user_roles AS
  SELECT user_id, role
  FROM public.user_roles;

-- Set ownership and permissions
ALTER TABLE public.users OWNER TO admin;
ALTER TABLE public.user_roles OWNER TO admin;

-- Grant permissions to authenticated users
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT ON api.users TO authenticated;

-- Grant permissions to admin
GRANT ALL ON ALL TABLES IN SCHEMA public TO admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO admin;
GRANT ALL ON ALL TABLES IN SCHEMA api TO admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA api TO admin;

-- Create extension for UUID generation if not exists
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- JWT authentication function
CREATE OR REPLACE FUNCTION api.authenticate(
  email text,
  password text
) RETURNS jsonb AS $$
BEGIN
  -- In production, this would verify against a password hash
  -- For now, we just return a dummy JWT
  RETURN jsonb_build_object(
    'token', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYXV0aGVudGljYXRlZCIsInVzZXJfaWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAiLCJleHAiOjE5OTk5OTk5OTl9',
    'expires_at', extract(epoch from now() + interval '1 day')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to get current user info
CREATE OR REPLACE FUNCTION api.get_current_user() RETURNS jsonb AS $$
BEGIN
  RETURN jsonb_build_object(
    'id', current_setting('request.jwt.claim.user_id', true),
    'role', current_setting('request.jwt.claim.role', true)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION api.authenticate TO anon;
GRANT EXECUTE ON FUNCTION api.get_current_user TO authenticated;

-- Create RLS policies
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Create policy that allows users to only see their own data
CREATE POLICY users_isolation ON public.users 
  FOR ALL
  TO authenticated
  USING (id::text = current_setting('request.jwt.claim.user_id', true));

-- Create policy that allows users to only see their own roles
CREATE POLICY user_roles_isolation ON public.user_roles 
  FOR SELECT
  TO authenticated
  USING (user_id::text = current_setting('request.jwt.claim.user_id', true));

-- Create policy for admins to see all data
CREATE POLICY admin_all ON public.users
  FOR ALL
  TO admin
  USING (true);

CREATE POLICY admin_all_roles ON public.user_roles
  FOR ALL
  TO admin
  USING (true);

-- SparkBaaS Database Initialization
-- This script sets up the initial database structure with proper security controls

-- Create custom schema for API
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'Schema for API accessible tables';

-- Create roles for different access patterns
CREATE ROLE anon;
COMMENT ON ROLE anon IS 'Anonymous role for unauthenticated access';

CREATE ROLE authenticated;
COMMENT ON ROLE authenticated IS 'Role for authenticated users';

CREATE ROLE service_role;
COMMENT ON ROLE service_role IS 'Role for trusted services';

-- Create the PostgREST authenticator role
CREATE ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}' NOINHERIT;
COMMENT ON ROLE authenticator IS 'PostgREST authenticator role';

-- Grant roles to authenticator
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Set search path for all transactions
ALTER ROLE authenticator SET search_path TO api, public;

-- For security, revoke all on schema public from public
REVOKE ALL ON SCHEMA public FROM public;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA api TO anon, authenticated, service_role;

-- Enable Row Level Security
ALTER DEFAULT PRIVILEGES IN SCHEMA api REVOKE ALL ON TABLES FROM public;

-- Create JWT verification function to extract user claims
CREATE OR REPLACE FUNCTION api.get_auth_claims() RETURNS jsonb AS $$
DECLARE
    _jwt_payload json;
    _jwt_header json;
    _jwt_claims jsonb;
BEGIN
    -- Get the JWT payload from the current request
    _jwt_payload := current_setting('request.jwt.claim', true)::json;
    
    IF _jwt_payload IS NULL THEN
        RETURN '{}'::jsonb;
    END IF;
    
    RETURN _jwt_payload::jsonb;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.get_auth_claims() IS 'Extracts JWT claims from the current request';

-- Create a function to get the current user's ID
CREATE OR REPLACE FUNCTION api.get_user_id() RETURNS text AS $$
DECLARE
    _claims jsonb;
BEGIN
    _claims := api.get_auth_claims();
    
    -- If no claims, return NULL (anonymous)
    IF _claims IS NULL OR _claims = '{}'::jsonb THEN
        RETURN NULL;
    END IF;
    
    -- Return the user ID from claims (supports multiple JWT formats)
    RETURN coalesce(
        _claims ->> 'sub',
        _claims ->> 'user_id',
        _claims ->> 'userId',
        _claims ->> 'id'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.get_user_id() IS 'Returns the current user ID from JWT claims';

-- Create a function to check if the user has a specific role
CREATE OR REPLACE FUNCTION api.has_role(required_role text) RETURNS boolean AS $$
DECLARE
    _claims jsonb;
    _roles jsonb;
BEGIN
    _claims := api.get_auth_claims();
    
    -- If no claims, return false
    IF _claims IS NULL OR _claims = '{}'::jsonb THEN
        RETURN FALSE;
    END IF;
    
    -- Try to extract roles from various JWT formats
    _roles := CASE
        WHEN _claims ? 'realm_access' THEN
            (_claims -> 'realm_access' -> 'roles')
        WHEN _claims ? 'roles' THEN
            _claims -> 'roles'
        ELSE NULL
    END;
    
    -- If we have roles as an array, check if the required role is in it
    IF _roles IS NOT NULL AND jsonb_typeof(_roles) = 'array' THEN
        RETURN _roles ? required_role;
    END IF;
    
    -- If we have a single role as a string
    IF _claims ? 'role' AND _claims ->> 'role' = required_role THEN
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.has_role(text) IS 'Checks if the current user has a specific role';

-- Create a function to check if a user is an admin
CREATE OR REPLACE FUNCTION api.is_admin() RETURNS boolean AS $$
BEGIN
    RETURN api.has_role('admin');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.is_admin() IS 'Checks if the current user is an admin';

-- Create a users table to store user information
CREATE TABLE IF NOT EXISTS api.users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE api.users IS 'Users table to track user information';

-- Grant access to users table
GRANT SELECT ON api.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.users TO service_role;

-- Enable RLS on users table
ALTER TABLE api.users ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY users_policy_select ON api.users
    FOR SELECT
    USING (
        id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY users_policy_insert ON api.users
    FOR INSERT
    WITH CHECK (
        id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY users_policy_update ON api.users
    FOR UPDATE
    USING (
        id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY users_policy_delete ON api.users
    FOR DELETE
    USING (
        api.is_admin()
    );

-- Create a table for storing application data
CREATE TABLE IF NOT EXISTS api.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES api.users(id) ON DELETE CASCADE,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE api.profiles IS 'User profiles with additional information';

-- Grant access to profiles table
GRANT SELECT ON api.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON api.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.profiles TO service_role;

-- Enable RLS on profiles table
ALTER TABLE api.profiles ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY profiles_policy_select ON api.profiles
    FOR SELECT
    USING (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY profiles_policy_insert ON api.profiles
    FOR INSERT
    WITH CHECK (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY profiles_policy_update ON api.profiles
    FOR UPDATE
    USING (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY profiles_policy_delete ON api.profiles
    FOR DELETE
    USING (
        api.is_admin()
    );

-- Create a table for items (example of user data)
CREATE TABLE IF NOT EXISTS api.items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES api.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE api.items IS 'Sample user items table with RLS policies';

-- Grant access to items table
GRANT SELECT ON api.items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.items TO service_role;

-- Enable RLS on items table
ALTER TABLE api.items ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for items
CREATE POLICY items_policy_select ON api.items
    FOR SELECT
    USING (
        user_id = api.get_user_id()
        OR is_public = TRUE
        OR api.is_admin()
    );

CREATE POLICY items_policy_insert ON api.items
    FOR INSERT
    WITH CHECK (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY items_policy_update ON api.items
    FOR UPDATE
    USING (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY items_policy_delete ON api.items
    FOR DELETE
    USING (
        user_id = api.get_user_id()
        OR api.is_admin()
    );

-- Create trigger function to automatically update the updated_at column
CREATE OR REPLACE FUNCTION api.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION api.update_timestamp() IS 'Automatically updates the updated_at timestamp';

-- Create triggers for tables to use the update_timestamp function
CREATE TRIGGER users_updated_at
BEFORE UPDATE ON api.users
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

CREATE TRIGGER profiles_updated_at
BEFORE UPDATE ON api.profiles
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

CREATE TRIGGER items_updated_at
BEFORE UPDATE ON api.items
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

-- Create view to expose public items
CREATE OR REPLACE VIEW api.public_items AS
SELECT id, name, description, created_at, updated_at
FROM api.items
WHERE is_public = TRUE;

COMMENT ON VIEW api.public_items IS 'Public items that can be viewed by anyone';

-- Grant access to public_items view
GRANT SELECT ON api.public_items TO anon, authenticated, service_role;

-- Create a table for function configurations
CREATE TABLE IF NOT EXISTS api.functions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_by TEXT REFERENCES api.users(id),
    runtime TEXT NOT NULL DEFAULT 'nodejs',
    memory_limit INTEGER NOT NULL DEFAULT 128,
    timeout_seconds INTEGER NOT NULL DEFAULT 30,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE api.functions IS 'Serverless function configurations';

-- Grant access to functions table
GRANT SELECT ON api.functions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.functions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.functions TO service_role;

-- Enable RLS on functions table
ALTER TABLE api.functions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for functions
CREATE POLICY functions_policy_select ON api.functions
    FOR SELECT
    USING (
        api.has_role('developer')
        OR api.is_admin()
    );

CREATE POLICY functions_policy_insert ON api.functions
    FOR INSERT
    WITH CHECK (
        api.has_role('developer')
        OR api.is_admin()
    );

CREATE POLICY functions_policy_update ON api.functions
    FOR UPDATE
    USING (
        created_by = api.get_user_id()
        OR api.is_admin()
    );

CREATE POLICY functions_policy_delete ON api.functions
    FOR DELETE
    USING (
        created_by = api.get_user_id()
        OR api.is_admin()
    );

-- Add trigger for functions table
CREATE TRIGGER functions_updated_at
BEFORE UPDATE ON api.functions
FOR EACH ROW
EXECUTE FUNCTION api.update_timestamp();

-- Create a security audit log table
CREATE TABLE IF NOT EXISTS api.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    user_id TEXT,
    ip_address TEXT,
    resource_type TEXT,
    resource_id TEXT,
    details JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE api.audit_logs IS 'Security audit logs';

-- Create index on audit_logs
CREATE INDEX audit_logs_event_type_idx ON api.audit_logs(event_type);
CREATE INDEX audit_logs_user_id_idx ON api.audit_logs(user_id);
CREATE INDEX audit_logs_occurred_at_idx ON api.audit_logs(occurred_at);

-- Grant access to audit_logs table
GRANT INSERT ON api.audit_logs TO authenticated, service_role;
GRANT SELECT ON api.audit_logs TO service_role;

-- Create a function to log audit events
CREATE OR REPLACE FUNCTION api.log_audit_event(
    event_type TEXT,
    resource_type TEXT DEFAULT NULL,
    resource_id TEXT DEFAULT NULL,
    details JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    _user_id TEXT;
    _ip_address TEXT;
    _log_id UUID;
BEGIN
    -- Get current user ID
    _user_id := api.get_user_id();
    
    -- Get IP address from request header
    _ip_address := current_setting('request.headers', true)::json->>'x-forwarded-for';
    
    -- Insert audit log
    INSERT INTO api.audit_logs (
        event_type,
        user_id,
        ip_address,
        resource_type,
        resource_id,
        details
    ) VALUES (
        event_type,
        _user_id,
        _ip_address,
        resource_type,
        resource_id,
        details
    ) RETURNING id INTO _log_id;
    
    RETURN _log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION api.log_audit_event(TEXT, TEXT, TEXT, JSONB)
IS 'Logs a security audit event';

-- Grant execute permission on the audit log function
GRANT EXECUTE ON FUNCTION api.log_audit_event(TEXT, TEXT, TEXT, JSONB)
TO authenticated, service_role;