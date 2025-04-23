// SparkBaaS Serverless Functions Server
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const crypto = require('crypto');
const { VM } = require('vm2');
const jwt = require('jsonwebtoken');
const morgan = require('morgan');
const fs = require('fs');
const path = require('path');
const { promisify } = require('util');

// Create Express app
const app = express();
const port = process.env.PORT || 3000;

// Configure middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Configure PostgreSQL connection
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@postgres:5432/sparkbaas',
  max: 20
});

// Function to verify JWT token from Keycloak
async function verifyToken(token) {
  try {
    // In production, fetch and cache the public key from Keycloak
    const publicKey = process.env.JWT_PUBLIC_KEY || 
      `-----BEGIN PUBLIC KEY-----
      MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnzyis1ZjfNB0bBgKFMSv
      vkTtwlvBsaJq7S5wA+kzeVOVpVWwkWdVha4s38XM/pa/yr47av7+z3VTmvDRyAHc
      aT92whREFpLv9cj5lTeJSibyr/Mrm/YtjCZVWgaOYIhwrXwKLqPr/11inWsAkfIy
      tvHWTxZYEcXLgAXFuUuaS3uF9gEiNQwzGTU1v0FqkqTBr4B8nW3HCN47XUu0t8Y0
      e+lf4s4OxQawWD79J9/5d3Ry0vbV3Am1FtGJiJvOwRsIfVChDpYStTcHTCMqtvWb
      V6L11BWkpzGXSW4Hv43qa+GSYOD2QU68Mb59oSk2OB+BtOLpJofmbGEGgvmwyCI9
      MwIDAQAB
      -----END PUBLIC KEY-----`;

    const decoded = jwt.verify(token, publicKey, { 
      algorithms: ['RS256'] 
    });
    
    return { valid: true, decoded };
  } catch (error) {
    console.error('JWT verification error:', error.message);
    return { valid: false, error: error.message };
  }
}

// Create a safe execution environment for user functions
function createSandbox(context) {
  // Time limit for function execution (30 seconds default)
  const timeLimit = context.functionConfig?.timeout_seconds || 30;
  
  // Memory limit
  const memoryLimit = context.functionConfig?.memory_limit || 128;
  
  // Create a secure VM with limited capabilities
  const vm = new VM({
    timeout: timeLimit * 1000,
    sandbox: {
      // Provide safe libraries and context to the function
      console: {
        log: (...args) => console.log(`[Function ${context.functionName}]:`, ...args),
        error: (...args) => console.error(`[Function ${context.functionName}]:`, ...args),
        warn: (...args) => console.warn(`[Function ${context.functionName}]:`, ...args),
      },
      // Pass request context to the function
      context,
      // Add other safe libraries as needed
      setTimeout,
      clearTimeout,
      // Add a fetch implementation
      fetch: async (url, options) => {
        const { default: nodeFetch } = await import('node-fetch');
        return nodeFetch(url, options);
      },
      Buffer,
      crypto: {
        randomUUID: crypto.randomUUID,
        randomBytes: crypto.randomBytes
      }
    },
    require: {
      external: {
        modules: [
          'lodash', 
          'axios', 
          'moment'
        ]
      },
      builtin: ['crypto', 'url', 'querystring', 'path']
    }
  });
  
  return vm;
}

// Function storage
const FUNCTIONS_DIR = process.env.FUNCTIONS_DIR || '/data/functions';

// Ensure functions directory exists
if (!fs.existsSync(FUNCTIONS_DIR)) {
  fs.mkdirSync(FUNCTIONS_DIR, { recursive: true });
}

// Get function code from storage
async function getFunctionCode(functionName) {
  try {
    const functionPath = path.join(FUNCTIONS_DIR, `${functionName}.js`);
    return await promisify(fs.readFile)(functionPath, 'utf8');
  } catch (err) {
    console.error(`Error reading function ${functionName}:`, err);
    return null;
  }
}

// Get function config from database
async function getFunctionConfig(functionName) {
  const client = await pgPool.connect();
  
  try {
    const result = await client.query(
      'SELECT * FROM api.functions WHERE name = $1 AND enabled = TRUE',
      [functionName]
    );
    
    if (result.rows.length === 0) {
      return null;
    }
    
    return result.rows[0];
  } catch (err) {
    console.error('Error fetching function config:', err);
    return null;
  } finally {
    client.release();
  }
}

// Log function execution
async function logFunctionExecution(functionName, userId, success, duration, error = null) {
  const client = await pgPool.connect();
  
  try {
    await client.query(
      `INSERT INTO api.log_audit_event($1, $2, $3, $4)`,
      [
        success ? 'function.execution.success' : 'function.execution.error',
        'function',
        functionName,
        JSON.stringify({
          duration_ms: duration,
          user_id: userId,
          error: error ? error.toString() : null
        })
      ]
    );
  } catch (err) {
    console.error('Error logging function execution:', err);
  } finally {
    client.release();
  }
}

// API endpoint to execute a function
app.post('/v1/functions/:name', async (req, res) => {
  const functionName = req.params.name;
  const startTime = Date.now();
  let userId = null;
  
  try {
    // Check authentication
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: Missing or invalid token' });
    }
    
    const token = authHeader.substring(7);
    const { valid, decoded, error } = await verifyToken(token);
    
    if (!valid) {
      return res.status(401).json({ error: `Unauthorized: ${error}` });
    }
    
    // Extract user ID from token
    userId = decoded.sub || decoded.user_id || decoded.id;
    
    // Get function configuration
    const functionConfig = await getFunctionConfig(functionName);
    if (!functionConfig) {
      return res.status(404).json({ error: `Function "${functionName}" not found or disabled` });
    }
    
    // Get function code
    const code = await getFunctionCode(functionName);
    if (!code) {
      return res.status(404).json({ error: `Function code for "${functionName}" not found` });
    }
    
    // Create execution context
    const context = {
      functionName,
      functionConfig,
      userId,
      request: {
        body: req.body,
        query: req.query,
        headers: req.headers,
        params: req.params
      },
      env: process.env.FUNCTION_ENV || 'production'
    };
    
    // Create sandbox
    const sandbox = createSandbox(context);
    
    // Execute the function
    const wrappedCode = `
      (async function() {
        ${code}
        
        // Call the handler function if it exists
        if (typeof handler !== 'function') {
          throw new Error('Function must export a handler function');
        }
        
        return await handler(context.request, context);
      })();
    `;
    
    const result = await sandbox.run(wrappedCode);
    
    // Log successful execution
    const duration = Date.now() - startTime;
    await logFunctionExecution(functionName, userId, true, duration);
    
    // Return the result
    res.json(result);
  } catch (error) {
    const duration = Date.now() - startTime;
    
    // Log failed execution
    await logFunctionExecution(functionName, userId, false, duration, error);
    
    console.error(`Error executing function ${functionName}:`, error);
    res.status(500).json({ 
      error: 'Function execution failed',
      message: error.message 
    });
  }
});

// API endpoint to check health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date() });
});

// Start the server
app.listen(port, () => {
  console.log(`SparkBaaS Functions Server listening on port ${port}`);
});