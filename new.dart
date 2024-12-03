
import 'dart:typed_data';

void main(){
  List<int> a = [-1, 100, 255, -128];
  Uint8List b = Uint8List.fromList(a);
  print(b);
  List<int> c = List<int>.empty(growable: true);
  c.addAll(b);
  Uint8List d = Uint8List.fromList(c);
  print(c);
  print(d);
  print(100 ~/ 3);
  print(100 % 3);
}