// ICU Devanagari-Latin for the Hinglish bench: one input line in, one line out.
import Foundation

let toLatin = StringTransform("Devanagari-Latin")
while let line = readLine() {
	print(line.applyingTransform(toLatin, reverse: false) ?? line)
}
