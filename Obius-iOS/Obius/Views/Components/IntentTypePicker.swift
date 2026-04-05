import SwiftUI

/// A picker for selecting the IntentType of a section or note
struct IntentTypePicker: View {
    @Binding var selectedIntent: IntentType
    let onSelect: (IntentType) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(IntentType.allCases, id: \.self) { intent in
                Button {
                    selectedIntent = intent
                    onSelect(intent)
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(intent.backgroundTint)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: intent.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(intent.color)
                        }
                        .overlay {
                            if selectedIntent == intent {
                                Circle()
                                    .stroke(intent.color, lineWidth: 2)
                                    .frame(width: 40, height: 40)
                            }
                        }
                        
                        Text(intent.displayName)
                            .font(.caption2)
                            .foregroundStyle(selectedIntent == intent ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

/// A button for selecting an intent type in a menu or list
struct IntentTypeButton: View {
    let intent: IntentType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Intent Rail preview
                RoundedRectangle(cornerRadius: 2)
                    .fill(intent.color)
                    .frame(width: 4, height: 24)
                
                Image(systemName: intent.icon)
                    .foregroundStyle(intent.color)
                    .frame(width: 24)
                
                Text(intent.displayName)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

/// A compact inline intent picker
struct CompactIntentPicker: View {
    @Binding var selectedIntent: IntentType
    let onChange: (IntentType) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(IntentType.allCases, id: \.self) { intent in
                Button {
                    selectedIntent = intent
                    onChange(intent)
                } label: {
                    Circle()
                        .fill(intent.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selectedIntent == intent {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Menu-based intent picker for toolbars
struct IntentTypeMenu: View {
    let currentIntent: IntentType
    let onSelect: (IntentType) -> Void

    var body: some View {
        Menu {
            ForEach(IntentType.allCases, id: \.self) { intent in
                Button {
                    onSelect(intent)
                } label: {
                    HStack {
                        Circle()
                            .fill(intent.color)
                            .frame(width: 10, height: 10)
                        Text(intent.displayName)
                        if currentIntent == intent {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Circle()
                .fill(currentIntent.color)
                .frame(width: 12, height: 12)
        }
    }
}

#Preview("Intent Type Pickers") {
    VStack(spacing: 32) {
        // Full picker
        IntentTypePicker(
            selectedIntent: .constant(.task),
            onSelect: { _ in }
        )
        
        Divider()
        
        // Button list
        VStack(spacing: 8) {
            ForEach(IntentType.allCases, id: \.self) { intent in
                IntentTypeButton(
                    intent: intent,
                    isSelected: intent == .question,
                    action: {}
                )
            }
        }
        .padding()
        
        Divider()
        
        // Compact picker
        CompactIntentPicker(
            selectedIntent: .constant(.evidence),
            onChange: { _ in }
        )
        .padding()
        
        Divider()
        
        // Menu picker
        IntentTypeMenu(
            currentIntent: .idea,
            onSelect: { _ in }
        )
        .padding()
    }
}
