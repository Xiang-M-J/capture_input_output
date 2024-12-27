import 'dart:typed_data';

List<int> uint8LtoInt16List(Uint8List rawData) {
  List<int> intArray = List.empty(growable: true);
  ByteData byteData = ByteData.sublistView(rawData);
  for (var i = 0; i < byteData.lengthInBytes; i += 2) {
    intArray.add(byteData.getInt16(i, Endian.little).toInt());
  }
  return intArray;
}

List<double> uint8LtoDoubleList(Uint8List rawData) {
  List<double> doubleArray = List.empty(growable: true);
  ByteData byteData = ByteData.sublistView(rawData);
  for (var i = 0; i < byteData.lengthInBytes; i += 2) {
    double v = byteData.getInt16(i, Endian.little).toInt() / 32768;
    if (v > 1.0) v=1.0;
    if (v < -1.0) v = -1.0;
    doubleArray.add(v);
  }
  return doubleArray;
}

doubleList2FloatList(List<List<double>> data) {
  List<Float32List> out = List.empty(growable: true);
  for (var i = 0; i < data.length; i++) {
    var floatList = Float32List.fromList(data[i]);
    out.add(floatList);
  }
  return out;
}

List<double> intList2doubleList(List<int> intData){
  List<double> doubleData = intData.map((e) => e / 32768).toList();
  return doubleData;
}

Uint8List doubleList2Uint8List(List<double> data){
  List<int> temp = data.map((e) => (e * 32768).toInt()).toList();
  Int16List int16Temp = Int16List.fromList(temp);
  final byteBuffer = ByteData(int16Temp.lengthInBytes);
  for (int i = 0; i < int16Temp.length; i++) {
    byteBuffer.setInt16(i * 2, int16Temp[i], Endian.little);
  }
  return byteBuffer.buffer.asUint8List();
}