import SwiftUI

// 月の開始日選択（1画面で完結）
struct MonthStartDayPickerView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(1...31, id: \.self) { day in
                Button {
                    settings.monthStartDay = day
                    dismiss()
                } label: {
                    HStack {
                        Text("\(day)日")
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.monthStartDay == day {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(UIColor.systemBlue))
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("月の開始日")
        .navigationBarTitleDisplayMode(.inline)
    }
}


