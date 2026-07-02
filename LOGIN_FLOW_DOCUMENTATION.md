# MSCE Exam App - Login Authentication Flow

## COMPLETE LOGIN PROCESS

### 1. INITIALIZATION (App Startup)

**File:** `lib/config/supabase_env.dart`

When the app starts:

1. App loads `app_config.env` file
2. Reads Supabase configuration:
   ```
   SUPABASE_URL=https://xxxx.supabase.co
   SUPABASE_ANON_KEY=sb_publishable_...
   ```

3. Initializes Supabase client with these credentials:
   ```dart
   await Supabase.initialize(
     url: url,
     anonKey: anonKey,
     httpClient: createSupabaseHttpClient(),
   );
   ```

4. Sets `_initialized = true` when ready
5. If failed → App still boots but login won't work (shows warning)

---

### 2. LOGIN SCREEN DISPLAY

**File:** `lib/screens/center_login_screen.dart`

User sees:
- "Exam Centre Login" title (with fade-in animation)
- "Welcome Back" message
- Two input fields:
  - Username field
  - Password field
- "LOGIN" button

---

### 3. LOGIN BUTTON PRESSED

**File:** `lib/screens/center_login_screen.dart` → `_submit()` method

When user taps LOGIN:

```dart
Future<void> _submit() async {
  if (_busy) return;  // Prevent multiple clicks
  if (!(_formKey.currentState?.validate() ?? false)) return;

  final user = _userCtrl.text.trim();  // Get username
  final pass = _passCtrl.text;          // Get password

  setState(() => _busy = true);  // Show loading state
  
  // Call authentication service
  final result = await _auth.login(user, pass);
  
  // Process result...
}
```

---

### 4. AUTHENTICATION SERVICE (Main Logic)

**File:** `lib/services/auth_service.dart` → `login()` method

This is where Supabase is called!

```dart
Future<...> login(String username, String password) async {
  
  // Step 1: Check if Supabase is configured
  if (!isSupabaseConfigured) {
    return (ok: false, message: 'Supabase not configured...');
  }

  try {
    // Step 2: Call Supabase RPC function
    final res = await supabase.rpc('exam_centre_login', params: {
      'p_username': username.trim().toLowerCase(),
      'p_password': password,
    });

    // Step 3: Parse RPC response
    final list = res as List;
    if (list.isEmpty) {
      return (ok: false, message: 'Login failed');
    }
    
    final map = Map<String, dynamic>.from(list[0] as Map);
    
    // Step 4: Check if login was successful
    if (map['ok'] != true) {
      return (
        ok: false, 
        message: map['message']?.toString() ?? 'Login failed'
      );
    }

    // Step 5: Return exam centre details
    return (
      ok: true,
      centerId: map['centre_id']?.toString(),
      code: map['centre_code']?.toString(),
      name: map['centre_name']?.toString(),
      msceInstituteId: map['exam_msce_institute_id']?.toString(),
      message: null,
    );
  } catch (e) {
    return (ok: false, message: e.toString());
  }
}
```

---

## WHAT HAPPENS AT EACH STEP

### Step 1: Username & Password Sent to Supabase

```
Device → Supabase
{
  "rpc_function": "exam_centre_login",
  "params": {
    "p_username": "centre_username",
    "p_password": "centre_password"
  }
}
```

**What Supabase does:**
- Receives username and password
- Looks up in exam_centres table
- Verifies password (uses hashing)
- If valid → returns centre details
- If invalid → returns error message

---

### Step 2: Supabase Returns Data

If login successful, Supabase returns:

```json
[{
  "ok": true,
  "centre_id": "123e4567-e89b-12d3-a456-426614174000",
  "centre_code": "CENTRE_001",
  "centre_name": "District School Exam Centre",
  "exam_msce_institute_id": "INST_123",
  "message": null
}]
```

If login failed:

```json
[{
  "ok": false,
  "centre_id": null,
  "centre_code": null,
  "centre_name": null,
  "exam_msce_institute_id": null,
  "message": "Username or password incorrect"
}]
```

---

### Step 3: App Processes Response

**File:** `lib/screens/center_login_screen.dart` → `_submit()` method

```dart
final result = await _auth.login(user, pass);

if (!result.ok || result.centerId == null) {
  // LOGIN FAILED
  setState(() => _busy = false);
  _showSnackbar(result.message ?? 'Login failed', success: false);
  // Error message shown at bottom of screen
  return;
}

// LOGIN SUCCESSFUL - Save centre details
await SessionService.saveCenter(
  centerId: result.centerId!,
  centerCode: result.code ?? '',
  centerName: result.name ?? '',
  msceInstituteId: result.msceInstituteId,
);

// Navigate to home screen
await PostLoginNavigator.continueSetup(context, centerId: result.centerId!);
```

---

### Step 4: Session Storage

**File:** `lib/services/session_service.dart`

After login, centre details are saved locally:

```dart
static Future<void> saveCenter({
  required String centerId,
  required String centerCode,
  required String centerName,
  required String msceInstituteId,
}) async {
  final prefs = await SharedPreferences.getInstance();
  
  // Save to device storage
  await prefs.setString('centre_id', centerId);
  await prefs.setString('centre_code', centerCode);
  await prefs.setString('centre_name', centerName);
  await prefs.setString('exam_msce_institute_id', msceInstituteId);
}
```

---

### Step 5: Navigate to Home Screen

After successful login:
- App navigates to Home Screen
- Loads all students for this centre
- Home screen queries: `exam_students` table with `centre_code` filter
- Shows all students allocated to this centre

---

## DATABASE LOOKUP FLOW

### Supabase RPC Function: `exam_centre_login`

The RPC function (backend stored procedure) does:

```
FUNCTION exam_centre_login(p_username TEXT, p_password TEXT):
  1. Look in exam_centres table
     WHERE username = p_username
  
  2. Check if password matches (hashed comparison)
  
  3. If match → Return:
     - ok: true
     - centre_id: (UUID from exam_centres.id)
     - centre_code: (from exam_centres.code)
     - centre_name: (from exam_centres.name)
     - exam_msce_institute_id: (from exam_centres.exam_msce_institute_id)
  
  4. If no match → Return:
     - ok: false
     - message: "Username or password incorrect"
```

---

## SECURITY FLOW

### What's Sent to Supabase:
- Username (as entered by user, but trimmed and lowercased)
- Password (plain text, sent over HTTPS)

### How Supabase Handles It:
1. **HTTPS Encryption** - All data encrypted in transit
2. **Password Hashing** - Database stores hashed passwords, not plain text
3. **SQL Injection Prevention** - Uses parameterized queries (RPC)
4. **Authentication** - Only anon key needed (public login endpoint)

### After Login:
- Centre ID stored in device's local storage (SharedPreferences)
- Used as filter for all subsequent queries:
  - Loading students: `WHERE centre_code = '[logged_in_centre]'`
  - Marking attendance: `WHERE centre_code = '[logged_in_centre]'`
  - QR scanning: `WHERE centre_code = '[logged_in_centre]'`

---

## ERROR SCENARIOS

### 1. Username Not Found
```
Supabase: No row in exam_centres with this username
Response: ok: false, message: "Username or password incorrect"
App: Shows red snackbar "Username or password incorrect"
```

### 2. Password Wrong
```
Supabase: Username found but password hash doesn't match
Response: ok: false, message: "Username or password incorrect"
App: Shows red snackbar "Username or password incorrect"
```

### 3. Supabase Not Configured
```
App: Checks isSupabaseConfigured before attempting login
Response: ok: false, message: "Supabase not configured. Fill app_config.env"
App: Shows error banner
```

### 4. Network Error
```
Request fails (no internet)
Exception caught in auth_service.dart
Response: ok: false, message: (error details)
App: Shows red snackbar with error
```

### 5. RPC Function Doesn't Exist
```
Supabase: RPC endpoint not found
Exception caught in auth_service.dart
Response: ok: false, message: (Supabase error)
App: Shows error message to user
```

---

## COMPLETE DATA FLOW DIAGRAM

```
┌─────────────────────────────────────┐
│   User Types Username & Password    │
│   and Taps LOGIN Button             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   center_login_screen.dart:_submit()│
│   Calls: _auth.login(user, pass)    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   AuthService.login()               │
│   Checks: isSupabaseConfigured      │
│   Calls: supabase.rpc(...)         │
└──────────────┬──────────────────────┘
               │
               ▼ (HTTPS Over Internet)
┌─────────────────────────────────────┐
│   SUPABASE CLOUD                    │
│   RPC: exam_centre_login()          │
│   Queries: exam_centres table       │
│   Checks username & password        │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
   (MATCH)      (NO MATCH)
        │             │
        ▼             ▼
   ok:true       ok:false
   (details)     (error msg)
        │             │
        └──────┬──────┘
               │
               ▼ (JSON Response)
┌─────────────────────────────────────┐
│   App Receives Response             │
│   Checks: result.ok                 │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
      SUCCESS       FAILURE
        │             │
        ▼             ▼
   Save Centre    Show Error
   Load Students  Snackbar
   Go to Home
```

---

## SUPABASE CONFIGURATION FILE

**File:** `app_config.env` (in project root)

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

These values are:
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_ANON_KEY` - Public API key (used for client-side auth)

---

## KEY FILES INVOLVED IN LOGIN

| File | Purpose |
|------|---------|
| `lib/screens/center_login_screen.dart` | UI - Login form, animations, user input |
| `lib/services/auth_service.dart` | Logic - Calls Supabase RPC function |
| `lib/config/supabase_env.dart` | Setup - Initializes Supabase client |
| `lib/core/supabase_client.dart` | Export - Makes supabase client available |
| `lib/services/session_service.dart` | Storage - Saves centre details locally |
| `app_config.env` | Config - Supabase URL and API key |

---

## SUMMARY

**Login Flow:**

1. User enters username & password on login screen
2. App sends to Supabase via `exam_centre_login` RPC
3. Supabase validates against `exam_centres` table
4. If valid → returns centre details (id, code, name, etc.)
5. If invalid → returns error message
6. App saves centre details to device storage
7. App navigates to home screen
8. All future queries filtered by centre_code

**Security:** HTTPS encryption + password hashing on database
**Data Source:** `exam_centres` table in Supabase PostgreSQL database

