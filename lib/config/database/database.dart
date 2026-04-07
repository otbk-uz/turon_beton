// ==========================================
// 6. BAZA MA'LUMOTLARI
// ==========================================
import 'package:flutter/material.dart';
import 'package:turon_beton/models/models.dart';

final List<String> masterTypesKeys = [
  'm_santexnik',
  'm_gisht',
  'm_elektrik',
  'm_qum',
  'm_payvand',
  'm_tom',
  'm_boyoq',
  'm_kafel',
  'm_duradgor',
  'm_betonchi'
];

final List<Map<String, String>> mastersDatabase = [
  {
    'name': 'Алишер Отабоев',
    'phone': '90 111 22 33',
    'address': 'Тошкент ш.',
    'typeKey': 'm_santexnik',
    'rating': '4.8'
  },
  {
    'name': 'Ботир Қодиров',
    'phone': '93 444 55 66',
    'address': 'Тошкент вил.',
    'typeKey': 'm_gisht',
    'rating': '5.0'
  },
];

final List<ProductModel> globalProducts = [
  ProductModel(
    id: 'beton',
    nameKey: 'prod_beton',
    icon: Icons.local_shipping,
    image:
        'https://images.unsplash.com/photo-1506555191898-a76bacf004ca?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'plita',
    nameKey: 'prod_plita',
    icon: Icons.view_comfy_alt,
    image:
        'https://images.unsplash.com/photo-1621252179027-94459d278660?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'kolodes',
    nameKey: 'prod_kolodes',
    icon: Icons.data_usage,
    image:
        'https://images.unsplash.com/photo-1590488421867-d9585ea1551a?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'blok',
    nameKey: 'prod_blok',
    icon: Icons.crop_square,
    image:
        'https://images.unsplash.com/photo-1587582423116-ec07293f0395?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'stolba',
    nameKey: 'prod_stolba',
    icon: Icons.format_align_center,
    image:
        'https://images.unsplash.com/photo-1563604479690-84dc248dbde1?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'qopqoq',
    nameKey: 'prod_qopqoq',
    icon: Icons.radio_button_unchecked,
    image:
        'https://images.unsplash.com/photo-1628189679313-097ec18b82ce?q=80&w=600&auto=format&fit=crop',
  ),
  ProductModel(
    id: 'lyuk',
    nameKey: 'prod_lyuk',
    icon: Icons.donut_small,
    image:
        'https://images.unsplash.com/photo-1601628828688-632f38a5a7d0?q=80&w=600&auto=format&fit=crop',
  ),
];
