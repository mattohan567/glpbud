import Foundation

/// Utility functions for weight conversion and validation
struct WeightUtils {
    // MARK: - Constants
    static let kgToLbsMultiplier = 2.20462
    static let lbsToKgMultiplier = 1.0 / kgToLbsMultiplier

    // Validation ranges (backend stores in kg, so kg ranges are authoritative)
    static let minWeightKg: Double = 20.0
    static let maxWeightKg: Double = 500.0
    static let minWeightLbs: Double = minWeightKg * kgToLbsMultiplier // 44.1
    static let maxWeightLbs: Double = maxWeightKg * kgToLbsMultiplier // 1102.3

    // MARK: - Conversion Functions

    /// Convert kilograms to pounds
    /// - Parameter kg: Weight in kilograms
    /// - Returns: Weight in pounds, rounded to 1 decimal place
    static func kgToLbs(_ kg: Double) -> Double {
        return round(kg * kgToLbsMultiplier * 10) / 10
    }

    /// Convert pounds to kilograms
    /// - Parameter lbs: Weight in pounds
    /// - Returns: Weight in kilograms, rounded to 1 decimal place
    static func lbsToKg(_ lbs: Double) -> Double {
        return round(lbs * lbsToKgMultiplier * 10) / 10
    }

    /// Convert weight from kg to user's preferred unit
    /// - Parameters:
    ///   - kg: Weight in kilograms
    ///   - toUnit: Target unit ("kg" or "lbs")
    /// - Returns: Converted weight value
    static func convertFromKg(_ kg: Double, toUnit unit: String) -> Double {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return kgToLbs(kg)
        default:
            return kg
        }
    }

    /// Convert weight to kg from user's input unit
    /// - Parameters:
    ///   - weight: Weight value in input unit
    ///   - fromUnit: Source unit ("kg" or "lbs")
    /// - Returns: Weight in kilograms
    static func convertToKg(_ weight: Double, fromUnit unit: String) -> Double {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return lbsToKg(weight)
        default:
            return weight
        }
    }

    // MARK: - Display Functions

    /// Format weight for display with appropriate unit label
    /// - Parameters:
    ///   - kg: Weight in kilograms (as stored in backend)
    ///   - unit: Display unit preference ("kg" or "lbs")
    ///   - includeUnit: Whether to include unit label in string
    /// - Returns: Formatted weight string
    static func displayWeight(_ kg: Double, unit: String, includeUnit: Bool = true) -> String {
        let convertedWeight = convertFromKg(kg, toUnit: unit)
        let weightStr = String(format: "%.1f", convertedWeight)

        if includeUnit {
            return "\(weightStr) \(unit)"
        } else {
            return weightStr
        }
    }

    /// Get placeholder text for weight input field
    /// - Parameter unit: Weight unit ("kg" or "lbs")
    /// - Returns: Appropriate placeholder text
    static func getPlaceholder(for unit: String) -> String {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return "e.g., 150.0"
        default:
            return "e.g., 70.0"
        }
    }

    // MARK: - Validation Functions

    /// Validate weight value for given unit
    /// - Parameters:
    ///   - weight: Weight value to validate
    ///   - unit: Unit of the weight value ("kg" or "lbs")
    /// - Returns: True if weight is within valid range
    static func validateWeight(_ weight: Double, unit: String) -> Bool {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return weight >= minWeightLbs && weight <= maxWeightLbs
        default:
            return weight >= minWeightKg && weight <= maxWeightKg
        }
    }

    /// Get validation error message for invalid weight
    /// - Parameter unit: Weight unit for appropriate error message
    /// - Returns: Error message string
    static func getValidationError(for unit: String) -> String {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return "Weight must be between \(String(format: "%.1f", minWeightLbs)) and \(String(format: "%.1f", maxWeightLbs)) lbs"
        default:
            return "Weight must be between \(String(format: "%.1f", minWeightKg)) and \(String(format: "%.1f", maxWeightKg)) kg"
        }
    }

    /// Get weight range description for unit
    /// - Parameter unit: Weight unit
    /// - Returns: Range description string
    static func getWeightRange(for unit: String) -> String {
        switch unit.lowercased() {
        case "lbs", "lb", "pounds":
            return "\(String(format: "%.0f", minWeightLbs))-\(String(format: "%.0f", maxWeightLbs)) lbs"
        default:
            return "\(String(format: "%.0f", minWeightKg))-\(String(format: "%.0f", maxWeightKg)) kg"
        }
    }

    // MARK: - Unit Helpers

    /// Check if unit string represents pounds
    /// - Parameter unit: Unit string to check
    /// - Returns: True if unit represents pounds
    static func isLbsUnit(_ unit: String) -> Bool {
        return ["lbs", "lb", "pounds"].contains(unit.lowercased())
    }

    /// Normalize unit string to standard format
    /// - Parameter unit: Input unit string
    /// - Returns: Normalized unit ("kg" or "lbs")
    static func normalizeUnit(_ unit: String) -> String {
        return isLbsUnit(unit) ? "lbs" : "kg"
    }
}