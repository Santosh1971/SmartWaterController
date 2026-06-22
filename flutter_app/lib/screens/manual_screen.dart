import 'package:flutter/material.dart';
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Manual Control')),
               body: const Center(child: CircularProgressIndicator()));
}
