import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../rooms/application/room_service.dart';
import '../../rooms/presentation/room_lobby_page.dart';

class AuthGate extends StatefulWidget {
  AuthGate({super.key, RoomService? service})
      : service = service ?? RoomService();

  final RoomService service;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.service.connect();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: widget.service.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null || snapshot.data!.isAnonymous) {
          return SignInPage(service: widget.service);
        }
        return RoomLobbyPage(service: widget.service);
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.service});

  final RoomService service;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  bool signUp = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (signUp) {
        await widget.service.signUp(
          email.text,
          password.text,
          displayName.text,
        );
      } else {
        await widget.service.signIn(email.text, password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = _authMessage(e));
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다.';
      case 'invalid-email':
        return '이메일 형식이 올바르지 않습니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 맞지 않습니다.';
      case 'weak-password':
        return '비밀번호는 6자 이상으로 입력해 주세요.';
      default:
        return e.message ?? '로그인에 실패했습니다.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로드나인 보스 알림')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  signUp ? '회원가입' : '로그인',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (signUp) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayName,
                    decoration: const InputDecoration(
                      labelText: '닉네임',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(signUp ? '가입하기' : '로그인'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            signUp = !signUp;
                            error = null;
                          }),
                  child: Text(signUp ? '이미 계정이 있어요' : '계정 만들기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
