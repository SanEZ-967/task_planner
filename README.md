=====================================================================
TASK PLANNER - SOURCE CODE README
=====================================================================
A Flutter (Android) task-planning app with a Firebase back end.

Features: email sign-up / sign-in with email verification, tasks with
priority (1-10), start/due dates, categories, subtasks, repeating tasks
(daily / every N days / chosen weekdays), time-tracked tasks (timer with
alert sound), count-tracked tasks (reps), a dashboard with streaks and
charts, due-date reminders, and appearance settings (theme, font size,
accent colour, avatar).

---------------------------------------------------------------------
1. TOOLS REQUIRED (install these first)
---------------------------------------------------------------------
Tool                   Version                         Download
---------------------  ------------------------------  ---------------------------------------------
Flutter SDK (stable)   3.35 or newer                   https://docs.flutter.dev/get-started/install
Dart SDK               Comes bundled with Flutter      (no separate install)
Android Studio          + Android SDK (via SDK Manager) https://developer.android.com/studio
JDK                    17 (bundled with Android Studio) (no separate install)
Git                    Any recent version              https://git-scm.com/downloads
VS Code (optional)     Any recent version, with the    https://code.visualstudio.com/
                       "Flutter" extension

Device to run on: an Android phone (USB debugging on) or an Android
emulator (API 26 or newer; Android 13+ recommended so the notification
permission prompt can be tested).


---------------------------------------------------------------------
2. BACK END (Firebase) - NO SETUP NEEDED TO RUN THE SUBMITTED CODE
---------------------------------------------------------------------
The submitted project is already connected to my Firebase project 
through lib/firebase_options.dart and android/app/google-services.json. 

How the data is organised in Cloud Firestore:
  users/{userId}/tasks/{taskId}   (one document per task)
Each user can only read and write their own tasks.

Firebase services used:
  - Authentication -> Sign-in method "Email/Password" enabled
  - Cloud Firestore

(OPTIONAL) To use your own Firebase project instead:
  1. Create a project at https://console.firebase.google.com
  2. Enable Authentication > Email/Password, and create a Firestore
     database.
  3. Install the FlutterFire CLI:  dart pub global activate flutterfire_cli
  4. In the project folder run:    flutterfire configure
     (choose Android; this regenerates lib/firebase_options.dart and
     android/app/google-services.json)
  5. Set these Firestore security rules:

     rules_version = '2';

     service cloud.firestore {
      match /databases/{database}/documents {
       match /users/{userId} {
        match /tasks/{taskId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
        }
       }
      }
     } 


---------------------------------------------------------------------
3. HOW TO RUN
---------------------------------------------------------------------
1. Download / clone the source code from the link at the top of this
   file. If it is a ZIP, extract it. 
2. Open a terminal inside the project folder (the one containing
   pubspec.yaml).
3. Check your setup:
       flutter doctor
   Fix anything marked with a red cross (usually accepting Android
   licences:  flutter doctor --android-licenses ).
4. Download the libraries:
       flutter pub get
5. Connect an Android phone or start an emulator, then confirm it is
   detected:
       flutter devices
6. Run the app:
       flutter run

To build an installable APK instead:
       flutter build apk --release
The file is created at build/app/outputs/flutter-apk/app-release.apk


---------------------------------------------------------------------
4. HOW TO TRY THE APP
---------------------------------------------------------------------
1. On the first screen choose "Create one", enter an email address you
   can open and a password of at least 6 characters.
2. Open the verification email, tap the link, then return to the app
   (it checks automatically every few seconds).
3. Tap the "+" button to add a task. Try: a normal task, a repeating
   task, a "Track by time" task (press play on the task list), and a
   "Track by count" task (tap the task's "+" badge to log a rep; long
   press to undo).
4. To delete a task, swipe the task left.
5. Open the Settings tab to turn on due-date reminders and choose the
   timer alert sound (use the play button to preview each sound).
   Allow notifications when Android asks.

---------------------------------------------------------------------
6. IMPORTANT NOTES
---------------------------------------------------------------------
- Platform: Android only. firebase_options.dart is configured for
  Android; running on web / iOS / desktop will show an "unsupported
  platform" error.
- An internet connection is needed to sign in and to load / save tasks.
- Notifications: for the timer alert to sound at the exact second, allow
  "Alarms & reminders" for the app when Android shows that screen
  (Android 12+). If it is not allowed, the alert may arrive a little
  late while the phone is idle.
- Timer alert sounds: custom sound files are stored in
  android/app/src/main/res/raw (timer_chime, timer_bell, timer_beep,
  timer_digital, timer_gentle). They are included in the submission.
- No dataset, images or other self-collected data are needed. All data
  is created by the user inside the app.


---------------------------------------------------------------------
7. PROJECT STRUCTURE (lib/ folder)
---------------------------------------------------------------------
  main.dart                          App start-up, theme, sign-in gate
  firebase_options.dart              Firebase connection settings (generated)
  models/task.dart                   Task + Subtask data, repeat logic, JSON
  services/notification_service.dart Reminders, timer alerts, sound channels
  screens/auth_screen.dart           Sign in / create account / reset password
  screens/verify_email_screen.dart   Email verification waiting screen
  screens/home_screen.dart           Main navigation, Firestore load/save
  screens/dashboard_screen.dart      Today, monthly, weekly stats and streaks
  screens/task_list_screen.dart      Task list, search, sort, date strip
  screens/add_task_screen.dart       Create / edit a task
  screens/settings_screen.dart       Theme, reminders, timer sound, clear data
  screens/profile_screen.dart        Name, avatar, font size, accent colour,
                                     sign out
