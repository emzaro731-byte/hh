# GG Messenger — Flutter

This folder is the Flutter conversion of the React Native app in the repository.

## Run

1. Install Flutter.
2. From `flutter_app/` run `flutter pub get`.
3. Supply your Supabase values:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

The existing Supabase database, storage buckets and Edge Functions remain the backend. The original React Native app is left untouched.

## Converted

- Supabase email authentication and password reset
- Conversation/user search
- Realtime chat and typing indicator
- Image/file attachments using `chat-media`
- Read/delivery state
- Dark mode
- AI Studio using the existing `ai-generate` and `ai-save` Edge Functions
- AI generation history

Voice/video calls and Firebase push notifications still require Android native configuration (`flutter_webrtc`/Firebase) and are intentionally kept separate from this first Flutter conversion rather than pretending the existing React Native modules are directly portable.
