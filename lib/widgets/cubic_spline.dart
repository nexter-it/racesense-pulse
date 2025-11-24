import 'dart:math';

class CubicSpline {
  final List<double> x;
  final List<double> y;
  late List<double> a, b, c, d;

  CubicSpline(this.x, this.y) {
    int n = x.length;
    a = List.from(y);
    b = List.filled(n - 1, 0.0);
    c = List.filled(n, 0.0);
    d = List.filled(n - 1, 0.0);

    // Step 1: Solve the system of equations
    List<double> h = List.filled(n - 1, 0.0);
    List<double> alpha = List.filled(n - 1, 0.0);

    for (int i = 0; i < n - 1; i++) {
      h[i] = x[i + 1] - x[i];
      if (h[i] == 0) {
        throw ArgumentError('x values must be distinct');
      }
    }

    for (int i = 1; i < n - 1; i++) {
      alpha[i] = (3.0 / h[i]) * (a[i + 1] - a[i]) -
          (3.0 / h[i - 1]) * (a[i] - a[i - 1]);
    }

    List<double> l = List.filled(n, 0.0);
    List<double> mu = List.filled(n - 1, 0.0);
    List<double> z = List.filled(n, 0.0);

    l[0] = 1.0;
    mu[0] = 0.0;
    z[0] = 0.0;

    for (int i = 1; i < n - 1; i++) {
      l[i] = 2.0 * (x[i + 1] - x[i - 1]) - h[i - 1] * mu[i - 1];
      mu[i] = h[i] / l[i];
      z[i] = (alpha[i] - h[i - 1] * z[i - 1]) / l[i];
    }

    l[n - 1] = 1.0;
    z[n - 1] = 0.0;
    c[n - 1] = 0.0;

    // Step 2: Back substitution
    for (int i = n - 2; i >= 0; i--) {
      c[i] = z[i] - mu[i] * c[i + 1];
      b[i] = (a[i + 1] - a[i]) / h[i] - h[i] * (c[i + 1] + 2.0 * c[i]) / 3.0;
      d[i] = (c[i + 1] - c[i]) / (3.0 * h[i]);
    }
  }

  double value(double xi) {
    int n = x.length;
    int i = 0;

    // Find the interval xi is in
    for (int j = 0; j < n - 1; j++) {
      if (xi >= x[j] && xi <= x[j + 1]) {
        i = j;
        break;
      }
    }

    // Calculate the cubic spline interpolation
    double dx = xi - x[i];
    return a[i] +
        b[i] * dx +
        c[i] * dx * dx +
        d[i] * dx * dx * dx;
  }

  List<double> interpolate(List<double> newX) {
    List<double> newY = [];
    for (var xi in newX) {
      newY.add(value(xi));
    }
    return newY;
  }
}
