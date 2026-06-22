import 'package:flutter/material.dart';
class CyclesScreen extends StatelessWidget {
  const CyclesScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Cycles')),
               body: const Center(child: CircularProgressIndicator()));
}
