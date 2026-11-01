import Foundation

/// Recursive descent parser; never evaluates executable code. Percent means divide by 100.
struct Calculator {
    private var chars: [Character]
    private var index = 0
    static func evaluate(_ input: String) throws -> Double {
        guard input.count <= 2048 else { throw ChaiError.message("算式過長") }
        var p = Calculator(chars: Array(input.filter { !$0.isWhitespace }))
        let value = try p.expression()
        guard p.index == p.chars.count, value.isFinite else { throw ChaiError.message("算式無效或結果超出範圍") }
        return value
    }
    private mutating func consume(_ c: Character) -> Bool {
        guard index < chars.count, chars[index] == c else { return false }
        index += 1; return true
    }
    private mutating func expression() throws -> Double {
        var v = try term()
        while index < chars.count {
            if consume("+") { v += try term() }
            else if consume("-") { v -= try term() }
            else { break }
        }
        return v
    }
    private mutating func term() throws -> Double {
        var v = try factor()
        while index < chars.count {
            if consume("*") { v *= try factor() }
            else if consume("/") {
                let d = try factor()
                guard d != 0 else { throw ChaiError.message("不能除以零") }; v /= d
            } else { break }
        }
        return v
    }
    private mutating func factor() throws -> Double {
        if consume("+") { return try factor() }
        if consume("-") { return -(try factor()) }
        var v: Double
        if consume("(") {
            v = try expression()
            guard consume(")") else { throw ChaiError.message("缺少右括號") }
        } else {
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            guard let n = Double(String(chars[start..<index])) else { throw ChaiError.message("請輸入有效數字與算式") }
            v = n
        }
        if consume("%") { v /= 100 }
        return v
    }
    static func convert(_ value: Double, from: String, to: String) throws -> Double {
        let units: [String: (String, Double)] = ["m":("長度",1),"cm":("長度",0.01),"km":("長度",1000),"in":("長度",0.0254),"ft":("長度",0.3048),"kg":("重量",1),"g":("重量",0.001),"lb":("重量",0.45359237)]
        if from == "°C", to == "°F" { return value * 9 / 5 + 32 }
        if from == "°F", to == "°C" { return (value - 32) * 5 / 9 }
        guard let a = units[from], let b = units[to], a.0 == b.0 else { throw ChaiError.message("不相容的單位") }
        return value * a.1 / b.1
    }
}
