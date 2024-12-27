import 'package:capture_input_ouput/utils/cutils.dart';
import 'package:capture_input_ouput/utils/type_converter.dart';



void main(){
  List<int> frame  = List.generate(1024, (i) => i * 20);
  List<double> wav = [];
  for(var i = 0; i < 4; i++){
    List<int> low = qmf(frame.sublist(i * 256, (i+1) * 256), 256, true);
    wav.addAll(intList2doubleList(low));
  }
  print(wav.length);
  print(wav);

}




