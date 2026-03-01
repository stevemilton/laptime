import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const sm = [
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color.fromRGBO(45, 27, 78, 0.06),
    ),
  ];

  static const md = [
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 12,
      color: Color.fromRGBO(45, 27, 78, 0.08),
    ),
  ];

  static const lg = [
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 32,
      color: Color.fromRGBO(45, 27, 78, 0.12),
    ),
  ];

  static const purple = [
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 20,
      color: Color.fromRGBO(91, 52, 145, 0.25),
    ),
  ];
}
