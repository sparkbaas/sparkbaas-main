#!/bin/bash

# SparkBaaS initialization script
echo "===== SparkBaaS Platform Initialization ====="
echo "Starting initialization process..."

# Check if PostgreSQL is ready
while ! nc -z postgres 5432; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done
echo "PostgreSQL is ready!"

# Run PostgreSQL initialization
echo "Initializing PostgreSQL databases and users..."
psql -h postgres -U ${POSTGRES_USER} -d ${POSTGRES_DB} -f /setup-scripts/postgres/init/01-init.sql

# Initialize Keycloak database
echo "Initializing Keycloak database..."
psql -h postgres -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE DATABASE keycloak WITH OWNER = keycloak;"

# Initialize Kong database
echo "Initializing Kong database..."
psql -h postgres -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE DATABASE kong WITH OWNER = kong;"

# Setup PostgREST schemas and roles
echo "Setting up PostgREST schemas and roles..."
psql -h postgres -U ${POSTGRES_USER} -d ${POSTGRES_DB} -f /setup-scripts/postgres/init/02-postgrest-setup.sql

# Generate default configuration files
echo "Generating configuration files..."

# Create Traefik dynamic configuration
mkdir -p /data/certificates
cat > /setup-scripts/traefik/dynamic_config.yml << EOF
http:
  middlewares:
    secure-headers:
      headers:
        browserXssFilter: true
        contentTypeNosniff: true
        frameDeny: true
        sslRedirect: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
EOF

# Generate default function server file
mkdir -p /setup-scripts/functions/
cat > /setup-scripts/functions/server.js << EOF
/**
 * SparkBaaS Function Server
 * 
 * This server provides a serverless function execution environment
 * for SparkBaaS. It dynamically loads and executes functions from
 * the functions directory.
 */
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const fs = require('fs-extra');
const path = require('path');
const { createWriteStream } = require('fs');

// Configuration
const PORT = process.env.PORT || 8888;
const AUTH_ENABLED = process.env.AUTH_ENABLED === 'true';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
const FUNCTIONS_DIR = path.join(__dirname, 'functions');

// Create app
const app = express();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logging
const accessLogStream = createWriteStream(path.join(__dirname, 'logs', 'access.log'), { flags: 'a' });
app.use(morgan('combined', { stream: accessLogStream }));
app.use(morgan('dev'));

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Authentication middleware (if enabled)
if (AUTH_ENABLED) {
  app.use((req, res, next) => {
    // JWT verification would go here
    // For now, just check if the Authorization header exists
    const authHeader = req.headers.authorization;
    
    // Skip auth for health check and OPTIONS requests
    if (req.path === '/health' || req.method === 'OPTIONS') {
      return next();
    }
    
    if (!authHeader) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Authentication required'
      });
    }
    
    // Here you would verify the JWT token
    // For now, we'll just pass it through
    next();
  });
}

// Function loader and router
async function loadFunctions() {
  try {
    // Ensure functions directory exists
    await fs.ensureDir(FUNCTIONS_DIR);
    
    // Read all function directories
    const functionDirs = await fs.readdir(FUNCTIONS_DIR);
    
    for (const fnDir of functionDirs) {
      const functionPath = path.join(FUNCTIONS_DIR, fnDir);
      const stats = await fs.stat(functionPath);
      
      if (stats.isDirectory()) {
        const configPath = path.join(functionPath, 'function.json');
        
        // Check if function.json exists
        if (await fs.pathExists(configPath)) {
          try {
            const config = await fs.readJson(configPath);
            const { name, handler } = config;
            
            if (name && handler) {
              const [handlerFile, handlerMethod] = handler.split('.');
              const handlerPath = path.join(functionPath, \`\${handlerFile}.js\`);
              
              if (await fs.pathExists(handlerPath)) {
                // Register route for this function
                console.log(\`Loading function: \${name} (\${handler})\`);
                
                // Route pattern will be /functions/:name
                app.all(\`/\${name}/*\`, async (req, res) => {
                  try {
                    // Clear require cache to allow hot reloading
                    delete require.cache[require.resolve(handlerPath)];
                    
                    // Load handler module
                    const handlerModule = require(handlerPath);
                    
                    // Check if handler method exists
                    if (typeof handlerModule[handlerMethod] === 'function') {
                      // Execute handler
                      const result = await handlerModule[handlerMethod](req, res);
                      
                      // If handler didn't end response, send result
                      if (!res.headersSent) {
                        res.json(result);
                      }
                    } else {
                      res.status(500).json({ error: \`Handler method \${handlerMethod} not found\` });
                    }
                  } catch (err) {
                    console.error(\`Error executing function \${name}:\`, err);
                    res.status(500).json({ error: err.message });
                  }
                });
                
                // Also add a direct route
                app.all(\`/\${name}\`, async (req, res) => {
                  try {
                    // Clear require cache to allow hot reloading
                    delete require.cache[require.resolve(handlerPath)];
                    
                    // Load handler module
                    const handlerModule = require(handlerPath);
                    
                    // Check if handler method exists
                    if (typeof handlerModule[handlerMethod] === 'function') {
                      // Execute handler
                      const result = await handlerModule[handlerMethod](req, res);
                      
                      // If handler didn't end response, send result
                      if (!res.headersSent) {
                        res.json(result);
                      }
                    } else {
                      res.status(500).json({ error: \`Handler method \${handlerMethod} not found\` });
                    }
                  } catch (err) {
                    console.error(\`Error executing function \${name}:\`, err);
                    res.status(500).json({ error: err.message });
                  }
                });
              }
            }
          } catch (err) {
            console.error(\`Error loading function \${fnDir}:\`, err);
          }
        }
      }
    }
  } catch (err) {
    console.error('Error loading functions:', err);
  }
}

// List available functions
app.get('/functions', async (req, res) => {
  try {
    const functionDirs = await fs.readdir(FUNCTIONS_DIR);
    const functions = [];
    
    for (const fnDir of functionDirs) {
      const functionPath = path.join(FUNCTIONS_DIR, fnDir);
      const stats = await fs.stat(functionPath);
      
      if (stats.isDirectory()) {
        const configPath = path.join(functionPath, 'function.json');
        
        if (await fs.pathExists(configPath)) {
          try {
            const config = await fs.readJson(configPath);
            functions.push({
              name: config.name,
              runtime: config.runtime,
              handler: config.handler,
              url: \`/\${config.name}\`
            });
          } catch (err) {
            console.error(\`Error reading function config \${fnDir}:\`, err);
          }
        }
      }
    }
    
    res.json(functions);
  } catch (err) {
    console.error('Error listing functions:', err);
    res.status(500).json({ error: err.message });
  }
});

// Start server
(async () => {
  // Load functions before starting server
  await loadFunctions();
  
  // Watch for changes in functions directory
  fs.watch(FUNCTIONS_DIR, { recursive: true }, async (eventType, filename) => {
    if (filename) {
      console.log(\`Function file changed: \${filename}\`);
      await loadFunctions();
    }
  });
  
  app.listen(PORT, () => {
    console.log(\`Function server running on port \${PORT}\`);
  });
})();
EOF

# Generate nginx config for admin UI
mkdir -p /setup-scripts/admin/
cat > /setup-scripts/admin/nginx.conf << EOF
server {
    listen 80;
    
    root /usr/share/nginx/html;
    index index.html;

    # Security headers
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; connect-src 'self' https://auth.* https://api.* https://db.* https://functions.*; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:";
    
    # SPA configuration
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # API proxies (if needed)
    location /api/ {
        proxy_pass http://kong:8000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires max;
        log_not_found off;
    }

    # Error page
    error_page 404 /index.html;
}
EOF

echo "Configuration files generated successfully."

# Run additional setup tasks

# Complete
echo "===== SparkBaaS initialization complete! ====="