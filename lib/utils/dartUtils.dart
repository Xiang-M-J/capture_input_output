import 'dart:math';

void swap(List<double> data, int i, int j) {
  double t = data[i];
  data[i] = data[j];
  data[j] = t;
}

// flag = 0 fft, flag = 1 ifft
List<double> fftIfft(List<double> input, int N, bool flag) {
  int mmax = 2, j = 0;
  int n = N << 1;
  int istep, m;
  double theta, wtemp, wpr, wpi, wr, wi, tempr, tempi;

  for (var i = 0; i < n - 1; i += 2) {
    if (j > i) {
      swap(input, j, i);
      swap(input, j + 1, i + 1);
    }
    m = n ~/ 2;
    while (m >= 2 && j >= m) {
      j -= m;
      m = m ~/ 2;
    }
    j += m;
  }

  while (n > mmax) {
    istep = mmax << 1;
    theta = -2 * pi / mmax;
    if (flag) theta = -theta;
    wtemp = sin(0.5 * theta);
    wpr = -2.0 * wtemp * wtemp;
    wpi = sin(theta);
    wr = 1.0;
    wi = 0.0;
    for (int m = 1; m < mmax; m += 2) {
      for (int i = m; i < n + 1; i += istep) {
        int j = i + mmax;
        tempr = wr * input[j - 1] - wi * input[j];
        tempi = wr * input[j] + wi * input[j - 1];
        input[j - 1] = input[i - 1] - tempr;
        input[j] = input[i] - tempi;
        input[i - 1] += tempr;
        input[i] += tempi;
      }
      wtemp = wr;
      wr += wr * wpr - wi * wpi;
      wi += wi * wpr + wtemp * wpi;
    }
    mmax = istep;
  }
  return input;
}

List<double> fft(List<double> input, int N){
  List<double> results = List.filled(2 * N, 0.0);

  for(int i = 0; i<N;i++){
    results[2 * i] = input[i];
  }

  results = fftIfft(results, N, false);
  return results;
}

List<double> ifft(List<double> input, int N){
  List<double> results = List.filled(N, 0.0);
  input = fftIfft(input, N, true);

  for(int i = 0; i<N; i++){
    results[i] = input[2 * i] / N;
  }
  return results;
}

List<double> stft(List<double> input, List<double> win, int frameSize){
  List<double> frame = List.filled(frameSize, 0.0);
  for(var i = 0; i<frameSize;i++){
    frame[i] = win[i] * input[i];
  }
  frame = fft(frame, frameSize);
  return frame;
}

List<double> istft(List<double> input, List<double> win, int frameSize){
  List<double> frame = ifft(input, frameSize);
  for(var i = 0; i<frameSize;i++){
    if (win[i] > 0.0000001){
      frame[i] = frame[i] / win[i];
    }
  }
  return frame;
}

void testStft1(){
  List<double> input = List.generate(128, (e)=> e / 128);
  List<double> win = List.generate(128, (e) => e / 128);
  int t1 = DateTime.now().microsecondsSinceEpoch;
  List<double> output = stft(input, win, 128);
  int t2 = DateTime.now().microsecondsSinceEpoch;
  print("dart: ${t2 - t1}");
}

void main(){
  List<double> input = List.generate(128, (e)=> e / 128);
  List<double> win = List.generate(128, (e) => e / 128);
  List<double> output = stft(input, win, 128);
  print(output);
}