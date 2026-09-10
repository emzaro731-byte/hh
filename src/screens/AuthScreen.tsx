import React, {useState} from 'react';
import {Alert, Pressable, SafeAreaView, StyleSheet, Text, TextInput, View} from 'react-native';
import {resetPassword, signIn, signUp} from '../lib/auth';

export default function AuthScreen({onAuthenticated}:{onAuthenticated:()=>void}) {
  const [signup, setSignup] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    if (!email || !password || (signup && !name)) return Alert.alert('Missing information','Complete all required fields.');
    setBusy(true);
    try {
      if (signup) { const data = await signUp(email,password,name); if (data.session) onAuthenticated(); else Alert.alert('Check your email','Confirm your email address, then sign in.'); }
      else { await signIn(email,password); onAuthenticated(); }
    } catch (e) { Alert.alert('Authentication failed', e instanceof Error ? e.message : 'Please try again.'); }
    finally { setBusy(false); }
  };
  const forgot = async () => { if (!email) return Alert.alert('Enter your email','Add your email first.'); try { await resetPassword(email); Alert.alert('Reset email sent','Check your inbox for the password reset link.'); } catch (e) { Alert.alert('Could not send reset email', e instanceof Error ? e.message : 'Try again.'); } };
  return <SafeAreaView style={styles.safe}><View style={styles.container}><View style={styles.logo}><Text style={styles.logoText}>GG</Text></View><Text style={styles.title}>{signup ? 'Create your account' : 'Welcome back'}</Text><Text style={styles.sub}>{signup ? 'Join GG Messenger and stay connected.' : 'Sign in to continue your conversations.'}</Text>{signup && <TextInput value={name} onChangeText={setName} placeholder="Display name" style={styles.input}/>}<TextInput value={email} onChangeText={setEmail} placeholder="Email address" autoCapitalize="none" keyboardType="email-address" style={styles.input}/><TextInput value={password} onChangeText={setPassword} placeholder="Password" secureTextEntry style={styles.input}/>{!signup && <Pressable onPress={forgot}><Text style={styles.forgot}>Forgot password?</Text></Pressable>}<Pressable style={styles.button} onPress={submit} disabled={busy}><Text style={styles.buttonText}>{busy ? 'Please wait…' : signup ? 'Create account' : 'Sign in'}</Text></Pressable><Pressable onPress={()=>setSignup(v=>!v)} style={styles.switch}><Text style={styles.switchText}>{signup ? 'Already have an account? Sign in' : 'New to GG? Create an account'}</Text></Pressable></View></SafeAreaView>;
}
const styles=StyleSheet.create({safe:{flex:1,backgroundColor:'#f7f8fa'},container:{flex:1,justifyContent:'center',padding:24},logo:{width:78,height:78,borderRadius:24,backgroundColor:'#111827',alignItems:'center',justifyContent:'center',alignSelf:'center',marginBottom:22},logoText:{color:'#fff',fontSize:30,fontWeight:'900'},title:{fontSize:28,fontWeight:'900',textAlign:'center',color:'#101828'},sub:{textAlign:'center',color:'#667085',fontSize:14,marginTop:7,marginBottom:25},input:{height:54,borderRadius:15,backgroundColor:'#fff',paddingHorizontal:16,fontSize:15,marginBottom:11,borderWidth:1,borderColor:'#eaecf0'},forgot:{color:'#2563eb',fontWeight:'700',textAlign:'right',marginBottom:16},button:{height:54,borderRadius:16,backgroundColor:'#2563eb',alignItems:'center',justifyContent:'center',marginTop:5},buttonText:{color:'#fff',fontSize:16,fontWeight:'800'},switch:{padding:18,alignItems:'center'},switchText:{color:'#2563eb',fontWeight:'700'}});
