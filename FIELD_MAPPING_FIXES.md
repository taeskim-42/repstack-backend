# Field Mapping Fixes for GenerateRoutine Mutation

## Overview
Fixed field mapping issues to ensure the iOS app receives all expected fields after the GraphQL mutation format change. The iOS client expects specific field names that need to match between the ClaudeApiService response and the GraphQL mutation response mapping.

## Changes Made

### 1. GenerateRoutine Mutation (`app/graphql/mutations/generate_routine.rb`)
**Fixed**: Missing `set_duration_seconds` field in the response mapping around line 30

**Before**:
```ruby
{
  exercise_name: ex["exerciseName"],
  # ... other fields ...
  rest_duration_seconds: ex["restDurationSeconds"],
  # setDurationSeconds was missing
}
```

**After**:
```ruby
{
  exercise_name: ex["exerciseName"],
  # ... other fields ...
  set_duration_seconds: ex["setDurationSeconds"],
  rest_duration_seconds: ex["restDurationSeconds"],
  # ... other fields ...
}
```

### 2. BodyInfoInputType (`app/graphql/types/body_info_input_type.rb`)
**Added**: Support for additional optional fields that might be sent by the iOS client

**Before**:
```ruby
argument :height, Float, required: false
argument :weight, Float, required: false
argument :body_fat, Float, required: false
```

**After**:
```ruby
argument :height, Float, required: false
argument :weight, Float, required: false
argument :body_fat, Float, required: false
argument :max_lifts, GraphQL::Types::JSON, required: false, description: "Maximum lift records as key-value pairs"
argument :recent_workouts, [GraphQL::Types::JSON], required: false, description: "Array of recent workout data"
```

### 3. ExerciseType (`app/graphql/types/exercise_type.rb`)
**Added**: Missing `set_duration_seconds` field to the GraphQL type definition

**Before**:
```ruby
field :bpm, Integer, null: true
field :rest_duration_seconds, Integer, null: true
# set_duration_seconds was missing
```

**After**:
```ruby
field :bpm, Integer, null: true
field :set_duration_seconds, Integer, null: true
field :rest_duration_seconds, Integer, null: true
```

### 4. ClaudeApiService (`app/services/claude_api_service.rb`)
**Fixed**: Updated mock routine and prompt template to include `setDurationSeconds` field

**Changes**:
- Added `"setDurationSeconds": 45` to the JSON template in `build_routine_prompt`
- Added `"setDurationSeconds"` field to all exercises in the `mock_routine` method
- Enhanced `format_body_info` method to handle the new optional fields (`max_lifts`, `recent_workouts`)

**Mock Exercise Example**:
```ruby
{
  "exerciseName" => "푸시업",
  "targetMuscle" => "chest",
  # ... other fields ...
  "setDurationSeconds" => 20,  # <-- Added this field
  "restDurationSeconds" => 60,
  # ... other fields ...
}
```

## iOS App Expected Fields
The iOS app expects these exercise fields, and all are now properly mapped:

✅ `exerciseName` → `exercise_name`  
✅ `targetMuscle` → `target_muscle`  
✅ `sets` → `sets`  
✅ `reps` → `reps`  
✅ `weight` → `weight`  
✅ `weightDescription` → `weight_description`  
✅ `bpm` → `bpm`  
✅ `setDurationSeconds` → `set_duration_seconds` (FIXED)  
✅ `restDurationSeconds` → `rest_duration_seconds`  
✅ `rangeOfMotion` → `range_of_motion`  
✅ `howTo` → `how_to`  
✅ `purpose` → `purpose`  

## Validation
- All Ruby files pass syntax validation
- Mock routine includes all required fields
- Field mapping from service response to GraphQL response tested and verified
- GraphQL mutation is properly registered in the schema

## Next Steps
- Test the complete flow with the iOS client
- Monitor for any additional field mismatches
- Consider adding integration tests for the mutation