import SwiftUI

struct SDCardsSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var tempCustomBucketName: [String: String] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        vm.clearIgnoresAndRefresh()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button {
                    Task { await vm.addSourceVolume() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Spacer()
                
                Toggle(isOn: $vm.debugScan) {
                    HStack(spacing: 4) {
                        Image(systemName: "ladybug.fill")
                        Text("Debug")
                            .lineLimit(1)
                    }
                    .font(.system(.caption, design: .rounded).weight(.medium))
                }
                .toggleStyle(.switch)
                .tint(.accentPrimary)
            }
            
            if vm.removableVolumes.isEmpty {
                emptyView
            } else {
                list
            }
            
            Spacer(minLength: 0)
        }
        .modernCard(accentColor: .accentSecondary)
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.title2)
                .foregroundColor(.accentSecondary)
            Text("SD Cards")
                .sectionHeader()
            Spacer()
            
            StatusBadge(
                text: "\(vm.removableVolumes.count) card\(vm.removableVolumes.count == 1 ? "" : "s")",
                color: vm.removableVolumes.isEmpty ? .secondary : .accentSecondary
            )
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No SD cards detected")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text("Insert an SD card or click 'Add SD Card'")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private var list: some View {
        LazyVStack(spacing: 12) {
            ForEach(vm.removableVolumes, id: \.self) { url in
                row(for: url)
            }
        }
    }
    
    private func row(for url: URL) -> some View {
        let volumeKey = vm.getVolumeRootPath(for: url) ?? ""
        let currentSavedBucket = vm.customBuckets[volumeKey] ?? "Auto-Detect"
        let isCustomSaved = !predefinedBuckets.contains(currentSavedBucket) && currentSavedBucket != "Auto-Detect"
        let isPickerCustom = (currentSavedBucket == "Custom..." || isCustomSaved)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.accentSecondary, .accentSecondary.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "externaldrive.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                bucketPicker(for: url, volumeKey: volumeKey, currentBucket: currentSavedBucket, isCustomSaved: isCustomSaved)
                
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        vm.removeVolumeFromList(for: url)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            
            if isPickerCustom {
                customFolderInput(for: url, volumeKey: volumeKey, currentBucket: currentSavedBucket, isCustomSaved: isCustomSaved)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentSecondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func bucketPicker(for url: URL, volumeKey: String, currentBucket: String, isCustomSaved: Bool) -> some View {
        Picker("Import Bucket", selection: Binding(
            get: {
                if isCustomSaved {
                    if self.tempCustomBucketName[volumeKey] == nil {
                        DispatchQueue.main.async {
                            self.tempCustomBucketName[volumeKey] = currentBucket
                        }
                    }
                    return "Custom..."
                }
                return currentBucket
            },
            set: { selectedBucket in
                if selectedBucket != "Custom..." {
                    vm.setCustomBucket(for: url, bucket: selectedBucket)
                    self.tempCustomBucketName.removeValue(forKey: volumeKey)
                } else {
                    let initialName = self.tempCustomBucketName[volumeKey] ?? currentBucket
                    let newCustomName = isCustomSaved ? initialName : "Custom Project"
                    self.tempCustomBucketName[volumeKey] = newCustomName
                    if newCustomName == "Custom Project" {
                        vm.setCustomBucket(for: url, bucket: newCustomName)
                    }
                }
            }
        )) {
            ForEach(predefinedBuckets, id: \.self) { bucketName in
                Text(bucketName).tag(bucketName)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .tint(.accentPrimary)
    }
    
    private func customFolderInput(for url: URL, volumeKey: String, currentBucket: String, isCustomSaved: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill.badge.gearshape")
                .foregroundColor(.accentPrimary)
                .font(.caption)
            
            TextField("Enter custom folder name", text: Binding(
                get: {
                    return self.tempCustomBucketName[volumeKey] ?? (isCustomSaved ? currentBucket : "Custom Project")
                },
                set: { newValue in
                    self.tempCustomBucketName[volumeKey] = newValue
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(.body, design: .rounded))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentPrimary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
            )
            .onSubmit {
                if let newBucket = self.tempCustomBucketName[volumeKey], !newBucket.isEmpty {
                    vm.setCustomBucket(for: url, bucket: newBucket)
                } else {
                    vm.setCustomBucket(for: url, bucket: "Custom Project")
                    self.tempCustomBucketName[volumeKey] = "Custom Project"
                }
            }
        }
        .padding(.leading, 56)
        .transition(.scale.combined(with: .opacity))
    }
}
