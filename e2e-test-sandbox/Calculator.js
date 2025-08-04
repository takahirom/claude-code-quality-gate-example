class Calculator {
  constructor() {
    this.history = [];
  }

  _validateNumbers(a, b) {
    if (typeof a !== 'number' || typeof b !== 'number') {
      throw new Error('Both arguments must be numbers');
    }
  }

  add(a, b) {
    this._validateNumbers(a, b);
    const result = a + b;
    this.history.push({ operation: 'add', operands: [a, b], result });
    return result;
  }

  subtract(a, b) {
    this._validateNumbers(a, b);
    const result = a - b;
    this.history.push({ operation: 'subtract', operands: [a, b], result });
    return result;
  }

  getHistory() {
    return this.history.slice();
  }

  clear() {
    this.history = [];
  }
}

module.exports = Calculator;