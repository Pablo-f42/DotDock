import Foundation

/// Evaluador de expresiones aritméticas.
///
/// Escrito a mano y no con `NSExpression` a propósito: `NSExpression(format:)` lanza
/// excepciones de Objective-C ante entrada malformada, y Swift no las puede capturar
/// — el proceso muere. Una calculadora recibe expresiones incompletas en cada
/// pulsación, así que ese camino es un crash garantizado.
///
/// Gramática (descenso recursivo, `^` asocia a la derecha):
///
///     expression := term (('+' | '-') term)*
///     term       := factor (('*' | '/' | '%') factor)*
///     factor     := unary ('^' factor)?
///     unary      := ('+' | '-') unary | primary
///     primary    := number | '(' expression ')'
///
enum ExpressionParser {

    /// Devuelve `nil` si la expresión está incompleta o es inválida. Nunca lanza.
    static func evaluate(_ input: String) -> Double? {
        guard let tokens = tokenize(input) else { return nil }
        guard !tokens.isEmpty else { return nil }

        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil }

        return value
    }

    // MARK: - Tokenizado

    fileprivate enum Token: Equatable {
        case number(Double)
        case plus, minus, star, slash, percent, caret
        case leftParen, rightParen
    }

    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        var chars = Array(input)
        var index = 0

        // Aceptamos coma como separador decimal: en un teclado en español es lo que
        // sale del teclado numérico.
        chars = chars.map { $0 == "," ? "." : $0 }

        while index < chars.count {
            let char = chars[index]

            if char.isWhitespace {
                index += 1
                continue
            }

            if char.isNumber || char == "." {
                var literal = ""
                var sawSeparator = false

                while index < chars.count, chars[index].isNumber || chars[index] == "." {
                    if chars[index] == "." {
                        // Un segundo punto en el mismo número es entrada inválida.
                        if sawSeparator { return nil }
                        sawSeparator = true
                    }
                    literal.append(chars[index])
                    index += 1
                }

                guard let value = Double(literal) else { return nil }
                tokens.append(.number(value))
                continue
            }

            let symbols: [Character: Token] = [
                "+": .plus, "-": .minus, "*": .star, "×": .star,
                "/": .slash, "÷": .slash, "%": .percent, "^": .caret,
                "(": .leftParen, ")": .rightParen
            ]

            guard let token = symbols[char] else { return nil }
            tokens.append(token)
            index += 1
        }

        return tokens
    }
}

// MARK: - Descenso recursivo

private struct Parser {

    let tokens: [ExpressionParser.Token]
    var index = 0

    var isAtEnd: Bool { index >= tokens.count }

    private var peek: ExpressionParser.Token? {
        isAtEnd ? nil : tokens[index]
    }

    private mutating func match(_ candidates: ExpressionParser.Token...) -> ExpressionParser.Token? {
        guard let token = peek, candidates.contains(token) else { return nil }
        index += 1
        return token
    }

    mutating func parseExpression() -> Double? {
        guard var result = parseTerm() else { return nil }

        while let op = match(.plus, .minus) {
            guard let rhs = parseTerm() else { return nil }
            result = op == .plus ? result + rhs : result - rhs
        }

        return result
    }

    private mutating func parseTerm() -> Double? {
        guard var result = parseFactor() else { return nil }

        while let op = match(.star, .slash, .percent) {
            guard let rhs = parseFactor() else { return nil }

            switch op {
            case .star:
                result *= rhs
            case .slash:
                // Dejamos pasar la división por cero: `evaluate` descarta los no
                // finitos al final, así que sale `nil` en vez de "inf".
                result /= rhs
            default:
                guard rhs != 0 else { return nil }
                result = result.truncatingRemainder(dividingBy: rhs)
            }
        }

        return result
    }

    private mutating func parseFactor() -> Double? {
        guard let base = parseUnary() else { return nil }
        guard match(.caret) != nil else { return base }

        // Recursión sobre `parseFactor` y no sobre `parseUnary`: `2^3^2` es 2^(3^2).
        guard let exponent = parseFactor() else { return nil }
        return pow(base, exponent)
    }

    private mutating func parseUnary() -> Double? {
        if let op = match(.plus, .minus) {
            guard let value = parseUnary() else { return nil }
            return op == .minus ? -value : value
        }

        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        guard let token = peek else { return nil }

        switch token {
        case .number(let value):
            index += 1
            return value

        case .leftParen:
            index += 1
            guard let value = parseExpression() else { return nil }
            guard match(.rightParen) != nil else { return nil }
            return value

        default:
            return nil
        }
    }
}
