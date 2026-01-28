# Expenlyst - Expense Tracker App

## Overview
Expenlyst is a Flutter-based expense tracking app with voice input, SQLite database, smart category detection, and Google Sheets sync.

## Tech Stack
- **Framework**: Flutter 3.x
- **Language**: Dart
- **Database**: SQLite (sqflite package)
- **State Management**: Provider
- **Speech Recognition**: speech_to_text
- **Storage**: shared_preferences (settings)
- **Cloud Sync**: Google Sheets API (googleapis)
- **Authentication**: Google Sign-In (google_sign_in)

## Project Structure
```
lib/
├── main.dart                    # App entry, theme, MultiProvider setup
├── models/
│   └── expense.dart             # Expense model (id, uuid, label, datetime, category, amount, tickerSinceAddUpdate, isDeleted, deviceId)
├── services/
│   ├── database_service.dart    # SQLite CRUD operations
│   ├── settings_service.dart    # Currency detection & persistence
│   ├── google_auth_service.dart # Google Sign-In/Sign-Out, token management
│   ├── sheets_service.dart      # Google Sheets API operations
│   └── sync_service.dart        # Upload/download sync, conflict resolution
├── providers/
│   ├── expense_provider.dart    # Expense state management
│   ├── settings_provider.dart   # Currency/settings state
│   └── sync_provider.dart       # Auth state, sync status, sheet selection
├── screens/
│   ├── home_screen.dart         # Main screen with summary + today's expenses
│   ├── all_expenses_screen.dart # All expenses grouped by date
│   └── settings_screen.dart     # Currency, theme, sync settings
└── widgets/
    ├── summary_card.dart        # Today total, weekly avg, monthly avg
    ├── expense_list.dart        # Today's expense list + Show All button
    ├── voice_input_button.dart  # Mic FAB with speech parsing & animations
    ├── sheet_picker_dialog.dart # Select existing or create new Google Sheet
    └── sync_status_indicator.dart # Sync progress/status display
```

## Database Schema
```sql
CREATE TABLE expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT,                     -- Cross-device unique ID
  label TEXT NOT NULL,
  datetime TEXT NOT NULL,        -- ISO 8601 format
  category TEXT NOT NULL,
  amount REAL NOT NULL,
  tickerSinceAddUpdate TEXT DEFAULT '0',  -- '0' initially, ISO 8601 on insert/update
  isDeleted INTEGER DEFAULT 0,   -- Soft delete flag for sync
  deviceId TEXT                  -- Originating device ID
);
CREATE INDEX idx_expenses_datetime ON expenses(datetime);
CREATE INDEX idx_expenses_ticker ON expenses(tickerSinceAddUpdate);
CREATE UNIQUE INDEX idx_expenses_uuid ON expenses(uuid);
```
**DB Version**: 4

### Migrations
- v1 → v2: Added datetime index
- v2 → v3: Added `tickerSinceAddUpdate` column (default '0')
- v3 → v4: Added `uuid`, `isDeleted`, `deviceId` columns for Google Sheets sync

## Key Features

### Voice Input
- Tap mic button to add expenses via speech
- Flexible parsing: "Coffee 50 rupees" or "50 uber"
- Smart category detection based on keywords
- Auto-category from previous expenses with same label

### Google Sheets Sync
- Sign in with Google to backup expenses
- Create new or select existing Expenlyst spreadsheet
- Incremental sync based on `tickerSinceAddUpdate` timestamp
- Conflict resolution using last-write-wins
- Restore data on new device from cloud
- Auto-sync option after each change
- Sign out wipes local data (recoverable via restore)

### Google Sheet Structure
| Column | Field | Description |
|--------|-------|-------------|
| A | uuid | Unique ID across devices |
| B | label | Expense label |
| C | datetime | ISO 8601 format |
| D | category | Category name |
| E | amount | Decimal amount |
| F | tickerSinceAddUpdate | Last modified timestamp |
| G | isDeleted | Soft delete flag (TRUE/FALSE) |
| H | deviceId | Originating device ID |

### Categories (40+)
- **Household**: Rent, Electricity, Water, Gas, Internet, Mobile Recharge, OTT
- **Food & Dining**: Groceries, Vegetables, Milk & Dairy, Snacks, Restaurants, Food Orders
- **Transportation**: Fuel, Public Transport, Cab, Parking, Toll, Car EMI
- **Shopping**: Clothing, Footwear, Accessories, Online Shopping, Electronics
- **Health**: Doctor, Medicines, Insurance, Gym
- **Education**: School Fees, Coaching, Online Courses, Books
- **Entertainment**: Movies, Games, Travel, Events, Hobbies
- **Financial**: Loan EMI, Credit Card, Investments, Taxes, Savings
- **Personal**: Salon, Kids, Gifts, Donations
- **Others**: Pet Care, Repairs, Emergency, Miscellaneous

### Currency Support
- Auto-detection from device timezone on first launch
- Manual override in Settings
- Supported: USD, EUR, GBP, INR, JPY, CAD, AUD

## Important Patterns

### Adding Expenses
1. Voice input parsed in `voice_input_button.dart` → `_parseExpense()`
2. Category detected in `_detectCategory()` using keyword matching
3. If label exists in DB, category auto-captured via `getCategoryByLabel()`
4. Expense saved via `ExpenseProvider.addExpense()`
5. If auto-sync enabled, triggers sync via `SyncProvider.triggerAutoSync()`

### State Management
- `ExpenseProvider`: Manages today/week/month expenses, calculates totals
  - `loadExpenses()` runs day/week/month queries in parallel via `Future.wait()`
- `SettingsProvider`: Manages currency selection and formatting
- `SyncProvider`: Manages Google auth, sync state, sheet selection

### Sync Flow
1. **Upload**: Get local changes since last sync → write to Google Sheet
2. **Download**: Read sheet → update local DB for newer cloud records
3. **Conflict**: Compare `tickerSinceAddUpdate` timestamps (last-write-wins)

### UI Components
- AppBar contains: Add expense (+), All expenses (list icon), Settings
- Cards use category-specific icons and colors from `ExpenseList.categoryIcons/categoryColors`
- Edit/Delete via PopupMenuButton (3-dot menu)
- Delete requires confirmation dialog
- Settings shows Google Account, Sync Settings (when signed in), Theme, Currency, Import

## Build & Run
```bash
flutter pub get
flutter run
```

## Google Cloud Console Setup (Required for Sync)
1. Create project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable APIs:
   - Google Sheets API
   - Google Drive API
3. Configure OAuth consent screen (External)
4. Add scopes:
   - `https://www.googleapis.com/auth/spreadsheets`
   - `https://www.googleapis.com/auth/drive.file`
5. Create OAuth credentials:
   - **Android**: Add package name (`com.drodify.expenlyst.expenlyst`) + SHA-1 fingerprint
   - **iOS**: Add Bundle ID
6. Download/configure credentials

### Getting SHA-1 (Android)
```bash
cd android
./gradlew signingReport
```

## Android Permissions
- `RECORD_AUDIO` - For speech recognition
- `INTERNET` - For speech services and Google Sheets sync

## iOS Permissions (Info.plist)
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

## Min SDK
- Android: minSdkVersion 21
- iOS: iOS 12.0+
