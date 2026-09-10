import React, {useEffect, useState} from 'react';
import {ActivityIndicator, SafeAreaView, StyleSheet, View} from 'react-native';
import {Session} from '@supabase/supabase-js';
import {supabase} from './lib/supabase';
import AuthScreen from './screens/AuthScreen';
import MessengerHome from './MessengerHome';

export default function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({data}) => { if (mounted) { setSession(data.session); setLoading(false); } });
    const {data: listener} = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => { mounted = false; listener.subscription.unsubscribe(); };
  }, []);

  if (loading) return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large" /></View></SafeAreaView>;
  return session ? <MessengerHome /> : <AuthScreen onAuthenticated={() => undefined} />;
}

const styles=StyleSheet.create({safe:{flex:1,backgroundColor:'#f7f8fa'},center:{flex:1,alignItems:'center',justifyContent:'center'}});
