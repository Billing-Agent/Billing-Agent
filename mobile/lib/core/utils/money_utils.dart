/// Centralized utility for handling monetary amounts.
/// 
/// In this application, financial values are represented as [String] 
/// in the data models to strictly prevent floating-point precision loss
/// during parsing from the backend. 
/// 
/// This utility converts the exact string representation into a localized 
/// format for presentation only. Business calculations should never use [double].
class MoneyUtils {
  
  /// Formats a string amount like "3450.00" into a display format "LKR 3,450.00".
  /// In a production app, use `intl` package. For Phase 4, a simple formatter suffices.
  static String formatAmount(String amount, {String currency = 'LKR'}) {
    // Basic formatting for presentation
    final parts = amount.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '00';

    // Add commas to integer part
    final buffer = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(integerPart[i]);
    }

    return '$currency ${buffer.toString()}.${decimalPart.padRight(2, '0')}';
  }
}
