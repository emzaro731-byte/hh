# VEYLORA AI

A production-ready Flutter starter for VEYLORA AI: chat UI, persistent conversations, configurable backend endpoint, and Material 3 dark UI.

## Run
```bash
flutter pub get
flutter run
```

## AI backend
Set the endpoint inside the app settings. The client accepts an OpenAI-compatible response (`choices[0].message.content`) or a simple JSON response containing `reply` or `text`.

For production, put your AI provider key on a server/Supabase Edge Function. Do not embed private API keys in the APK.
