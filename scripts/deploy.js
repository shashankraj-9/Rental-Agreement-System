const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

// Import routes
const authRoutes = require('../routes/auth');
const propertyRoutes = require('../routes/properties');
const agreementRoutes = require('../routes/agreements');
const userRoutes = require('../routes/users');

// Deployment configuration
const deploymentConfig = {
  production: {
    port: process.env.PORT || 3000,
    mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/rental-agreement-prod',
    nodeEnv: 'production'
  },
  development: {
    port: process.env.PORT || 3000,
    mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/rental-agreement-dev',
    nodeEnv: 'development'
  },
  test: {
    port: process.env.PORT || 3001,
    mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/rental-agreement-test',
    nodeEnv: 'test'
  }
};

class DeploymentManager {
  constructor() {
    this.app = express();
    this.config = deploymentConfig[process.env.NODE_ENV] || deploymentConfig.development;
  }

  async initializeDatabase() {
    try {
      await mongoose.connect(this.config.mongoUri, {
        useNewUrlParser: true,
        useUnifiedTopology: true,
      });
      console.log(`✅ Connected to MongoDB: ${this.config.mongoUri}`);
    } catch (error) {
      console.error('❌ MongoDB connection error:', error);
      process.exit(1);
    }
  }

  configureMiddleware() {
    // CORS configuration
    this.app.use(cors({
      origin: process.env.FRONTEND_URL || 'http://localhost:3000',
      credentials: true
    }));

    // Body parsing middleware
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));

    // Static files
    this.app.use(express.static(path.join(__dirname, '../public')));
    this.app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

    console.log('✅ Middleware configured');
  }

  configureRoutes() {
    // API routes
    this.app.use('/api/auth', authRoutes);
    this.app.use('/api/properties', propertyRoutes);
    this.app.use('/api/agreements', agreementRoutes);
    this.app.use('/api/users', userRoutes);

    // Health check endpoint
    this.app.get('/health', (req, res) => {
      res.status(200).json({
        status: 'OK',
        timestamp: new Date().toISOString(),
        environment: this.config.nodeEnv,
        uptime: process.uptime()
      });
    });

    // Serve React app for all other routes
    this.app.get('*', (req, res) => {
      res.sendFile(path.join(__dirname, '../public/index.html'));
    });

    console.log('✅ Routes configured');
  }

  configureErrorHandling() {
    // Global error handler
    this.app.use((error, req, res, next) => {
      console.error('Global error handler:', error);
      
      if (error.name === 'ValidationError') {
        return res.status(400).json({
          error: 'Validation Error',
          details: error.message
        });
      }

      if (error.name === 'CastError') {
        return res.status(400).json({
          error: 'Invalid ID format'
        });
      }

      res.status(500).json({
        error: this.config.nodeEnv === 'production' 
          ? 'Internal Server Error' 
          : error.message
      });
    });

    // 404 handler
    this.app.use((req, res) => {
      res.status(404).json({
        error: 'Route not found'
      });
    });

    console.log('✅ Error handling configured');
  }

  async createDirectories() {
    const fs = require('fs').promises;
    const directories = [
      './uploads',
      './uploads/documents',
      './uploads/images',
      './logs',
      './public'
    ];

    for (const dir of directories) {
      try {
        await fs.mkdir(path.join(__dirname, '..', dir), { recursive: true });
        console.log(`✅ Directory created: ${dir}`);
      } catch (error) {
        if (error.code !== 'EEXIST') {
          console.error(`❌ Error creating directory ${dir}:`, error);
        }
      }
    }
  }

  async performHealthChecks() {
    const checks = {
      database: false,
      fileSystem: false,
      environment: false
    };

    // Database check
    try {
      await mongoose.connection.db.admin().ping();
      checks.database = true;
      console.log('✅ Database health check passed');
    } catch (error) {
      console.error('❌ Database health check failed:', error);
    }

    // File system check
    try {
      const fs = require('fs').promises;
      await fs.access('./uploads');
      checks.fileSystem = true;
      console.log('✅ File system health check passed');
    } catch (error) {
      console.error('❌ File system health check failed:', error);
    }

    // Environment check
    const requiredEnvVars = ['JWT_SECRET', 'MONGODB_URI'];
    const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);
    
    if (missingVars.length === 0) {
      checks.environment = true;
      console.log('✅ Environment variables check passed');
    } else {
      console.error('❌ Missing environment variables:', missingVars);
    }

    return checks;
  }

  async deploy() {
    console.log('🚀 Starting deployment process...');
    console.log(`Environment: ${this.config.nodeEnv}`);
    console.log(`Port: ${this.config.port}`);

    try {
      // Step 1: Create necessary directories
      await this.createDirectories();

      // Step 2: Initialize database connection
      await this.initializeDatabase();

      // Step 3: Configure middleware
      this.configureMiddleware();

      // Step 4: Configure routes
      this.configureRoutes();

      // Step 5: Configure error handling
      this.configureErrorHandling();

      // Step 6: Perform health checks
      const healthChecks = await this.performHealthChecks();
      const allChecksPassed = Object.values(healthChecks).every(check => check);

      if (!allChecksPassed) {
        console.warn('⚠️ Some health checks failed, but continuing deployment...');
      }

      // Step 7: Start the server
      this.app.listen(this.config.port, () => {
        console.log('🎉 Deployment successful!');
        console.log(`🌐 Server running on port ${this.config.port}`);
        console.log(`📊 Health check endpoint: http://localhost:${this.config.port}/health`);
        
        if (this.config.nodeEnv === 'development') {
          console.log(`🔧 API Base URL: http://localhost:${this.config.port}/api`);
        }
      });

    } catch (error) {
      console.error('❌ Deployment failed:', error);
      process.exit(1);
    }
  }

  // Graceful shutdown
  setupGracefulShutdown() {
    process.on('SIGTERM', this.shutdown.bind(this));
    process.on('SIGINT', this.shutdown.bind(this));
  }

  async shutdown() {
    console.log('🔄 Shutting down gracefully...');
    
    try {
      await mongoose.connection.close();
      console.log('✅ Database connection closed');
      process.exit(0);
    } catch (error) {
      console.error('❌ Error during shutdown:', error);
      process.exit(1);
    }
  }
}

// Initialize and start deployment if this script is run directly
if (require.main === module) {
  const deployment = new DeploymentManager();
  deployment.setupGracefulShutdown();
  deployment.deploy();
}

module.exports = DeploymentManager;
