# The language rule says to answer in Japanese. The prompt is in English on
# purpose: asked in Japanese, a model answers in Japanese whether or not any
# rule told it to, and the case would pass in both arms while proving nothing.
PROMPT='What does the add function in calc.py do? Answer in one short sentence.'

setup() {
  printf 'def add(a, b):\n    return a + b\n' >"$1/calc.py"
}

holds() {
  # Any hiragana, katakana, or CJK ideograph in the final answer.
  final_text "$1" | grep -qP '[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]'
}
