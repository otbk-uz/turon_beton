// ==========================================
// 2. MODELLAR (O'zgarmadi - Business Logic)
// ==========================================
import 'package:flutter/material.dart';

enum UserRole { client, master, admin }

class UserModel {
  final String phone;
  final String name;
  final String address;
  final String avatar;
  final UserRole role;
  final String? masterTypeKey;

  UserModel({
    required this.phone,
    required this.name,
    required this.address,
    this.avatar = '',
    this.role = UserRole.client,
    this.masterTypeKey,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isMaster => role == UserRole.master;
}

class CartItem {
  final String id;
  final String name;
  final String details;
  final int qty;
  final String? meters;
  final double price;
  final double dostavka;

  CartItem({
    required this.id,
    required this.name,
    required this.details,
    required this.qty,
    this.meters,
    required this.price,
    this.dostavka = 0.0,
  });

  double get totalPrice => (price * qty) + dostavka;
}

class ProductModel {
  final String id;
  final String nameKey;
  final IconData icon;
  final String image;

  ProductModel({
    required this.id,
    required this.nameKey,
    required this.icon,
    required this.image,
  });
}

class OrderModel {
  final String id;
  final String userName;
  final String userPhone;
  final String userAddress;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime date;
  final String status;

  OrderModel({
    required this.id,
    required this.userName,
    required this.userPhone,
    required this.userAddress,
    required this.items,
    required this.totalAmount,
    required this.date,
    this.status = 'KUTILMOQDA...',
  });

  Map<String, dynamic> toFirebaseJson() => {
        'userName': userName,
        'userPhone': userPhone,
        'userAddress': userAddress,
        'itemsText': items.map((e) => "${e.qty}x ${e.name}").join("\n"),
        'totalAmount': totalAmount.toStringAsFixed(0),
        'date': date.toString().substring(0, 16),
        'status': status,
      };
}
