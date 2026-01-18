# RepStack Backend

A comprehensive Rails 8 API backend for fitness tracking and AI-powered workout routine generation.

## 🏃‍♂️ Features

### ✨ Core Functionality
- **User Authentication** - JWT-based authentication system
- **User Profiles** - Detailed fitness profile management
- **Workout Tracking** - Log workout sessions and individual sets
- **AI Routine Generation** - Claude AI-powered workout routine creation
- **GraphQL API** - Complete GraphQL interface for all operations

### 🔐 Authentication & Authorization
- Secure user registration and login
- JWT token-based authentication
- Password encryption with bcrypt
- Protected GraphQL resolvers

### 🗄️ Data Models
- **Users** - User accounts with secure authentication
- **UserProfiles** - Fitness goals, measurements, and progress tracking
- **WorkoutSessions** - Individual workout session tracking
- **WorkoutSets** - Detailed exercise set logging
- **WorkoutRoutines** - AI-generated workout routines
- **RoutineExercises** - Detailed exercise specifications

### 🤖 AI Integration
- **Claude API Integration** - Generates personalized workout routines
- **Smart Recommendations** - Based on user level, goals, and history
- **Adaptive Programming** - Routines adjust based on user progress

## 🚀 Quick Start

### Prerequisites
- Ruby 3.0+ 
- PostgreSQL
- Bundler
- Claude API Key (for AI features)

### Installation

1. **Clone and setup**
   ```bash
   git clone <repository-url>
   cd repstack-backend
   ruby setup.rb  # Run setup verification script
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Database setup**
   ```bash
   rails db:create
   rails db:migrate
   ```

4. **Environment configuration**
   ```bash
   # Update .env file with your Claude API key
   ANTHROPIC_API_KEY=your_claude_api_key_here
   ```

5. **Start the server**
   ```bash
   rails server
   ```

## 📖 API Documentation

### GraphQL Endpoint
- **URL**: `http://localhost:3000/graphql`
- **Method**: POST
- **Content-Type**: application/json

### Authentication
Include JWT token in Authorization header:
```
Authorization: Bearer <your-jwt-token>
```

### Key Mutations

#### User Registration
```graphql
mutation {
  signUp(email: "user@example.com", password: "password123", name: "User Name") {
    authPayload {
      token
      user {
        id
        email
        name
      }
    }
    errors
  }
}
```

#### Generate AI Workout
```graphql
mutation {
  generateRoutine(
    level: "beginner"
    week: 1
    day: 1
    bodyInfo: {
      height: 175.0
      weight: 70.0
      bodyFat: 15.0
    }
  ) {
    routine {
      workoutType
      estimatedDuration
      exercises {
        exerciseName
        sets
        reps
        howTo
        purpose
      }
    }
  }
}
```

#### Track Workout
```graphql
# Start session
mutation {
  createWorkoutSession(name: "Morning Workout") {
    id
    startTime
  }
}

# Log exercise sets
mutation {
  logWorkoutSet(
    sessionId: "1"
    setInput: {
      exerciseName: "Push-ups"
      reps: 10
      weight: 0
    }
  ) {
    id
    exerciseName
    reps
  }
}
```

### Key Queries

#### User Information
```graphql
query {
  me {
    id
    email
    name
    userProfile {
      height
      weight
      currentLevel
      fitnessGoal
    }
  }
}
```

#### Workout History
```graphql
query {
  mySessions(limit: 10) {
    id
    name
    startTime
    endTime
    workoutSets {
      exerciseName
      weight
      reps
    }
  }
}
```

## 🏗️ Architecture

### Technology Stack
- **Rails 8** - API framework
- **PostgreSQL** - Primary database
- **GraphQL** - API query language
- **JWT** - Authentication tokens
- **bcrypt** - Password encryption
- **Faraday** - HTTP client for Claude API

### Project Structure
```
app/
├── controllers/       # API controllers with authentication
├── models/           # ActiveRecord models
├── services/         # Business logic services
└── graphql/          # GraphQL schema, types, mutations, queries
db/
├── migrate/          # Database migrations
└── schema.rb         # Database schema
```

### Database Schema
- **users** - User accounts and authentication
- **user_profiles** - Fitness profiles and goals
- **workout_sessions** - Workout session tracking
- **workout_sets** - Individual exercise sets
- **workout_routines** - AI-generated routines
- **routine_exercises** - Exercise details in routines

## 🧪 Testing

### Manual Testing
1. Start server: `rails server`
2. Open GraphQL playground/client
3. Use example queries and mutations
4. Verify authentication with JWT tokens

### Model Testing
```bash
rails console

# Test user creation
user = User.create(email: "test@example.com", password: "password", name: "Test")
profile = user.create_user_profile(current_level: "beginner")

# Test associations
user.user_profile
profile.user
```

## 🔧 Configuration

### Environment Variables (.env)
```bash
# Required
ANTHROPIC_API_KEY=your_claude_api_key
JWT_SECRET_KEY=your_jwt_secret

# Optional
DATABASE_URL=postgresql://user:password@localhost/repstack_backend
RAILS_ENV=development
```

### Database Configuration
Configure PostgreSQL settings in `config/database.yml`

## 📚 Additional Documentation

- **IMPLEMENTATION_STATUS.md** - Complete implementation details and API examples
- **setup.rb** - Setup verification script
- **GraphQL Schema** - Auto-generated documentation available via introspection

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Implement changes with tests
4. Submit pull request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For questions or issues:
1. Check IMPLEMENTATION_STATUS.md for detailed API documentation
2. Run `ruby setup.rb` to verify setup
3. Check server logs for debugging
4. Ensure PostgreSQL and Ruby environment are properly configured

---

**Built with ❤️ for fitness enthusiasts who want AI-powered workout planning and comprehensive tracking.**