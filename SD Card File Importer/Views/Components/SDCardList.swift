import SwiftUI

enum MediaType {
    case photos
    case videos
}

struct SDCardsSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var tempCustomPhotosName: [String: String] = [:]
    @State private var tempCustomVideosName: [String: String] = [:]
    @State private var isPulsing = false
    
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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentSecondary.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 0 : 1)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: isPulsing)
                
                Circle()
                    .fill(Color.accentSecondary.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "sdcard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.accentSecondary)
            }
            .padding(.top, 10)
            
            VStack(spacing: 4) {
                Text("Waiting for Media")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                Text("Insert an SD card or click 'Add'")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .onAppear { isPulsing = true }
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
        
        let currentPhotosBucket = vm.customBucketsPhotos[volumeKey] ?? "Auto-Detect"
        let isPhotosCustomSaved = !vm.dropdownBuckets.contains(currentPhotosBucket) && currentPhotosBucket != "Auto-Detect"
        let isPhotosPickerCustom = (currentPhotosBucket == "Custom..." || isPhotosCustomSaved)
        
        let currentVideosBucket = vm.customBucketsVideos[volumeKey] ?? "Auto-Detect"
        let isVideosCustomSaved = !vm.dropdownBuckets.contains(currentVideosBucket) && currentVideosBucket != "Auto-Detect"
        let isVideosPickerCustom = (currentVideosBucket == "Custom..." || isVideosCustomSaved)
        
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
            
            Divider()
                .padding(.vertical, 2)
                
            HStack(spacing: 8) {
                Text("Photos")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
                
                bucketPicker(for: url, volumeKey: volumeKey, currentBucket: currentPhotosBucket, isCustomSaved: isPhotosCustomSaved, mediaType: .photos)
                
                if isPhotosPickerCustom {
                    customFolderInput(for: url, volumeKey: volumeKey, currentBucket: currentPhotosBucket, isCustomSaved: isPhotosCustomSaved, mediaType: .photos)
                }
                Spacer()
            }
            
            HStack(spacing: 8) {
                Text("Videos")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
                
                bucketPicker(for: url, volumeKey: volumeKey, currentBucket: currentVideosBucket, isCustomSaved: isVideosCustomSaved, mediaType: .videos)
                
                if isVideosPickerCustom {
                    customFolderInput(for: url, volumeKey: volumeKey, currentBucket: currentVideosBucket, isCustomSaved: isVideosCustomSaved, mediaType: .videos)
                }
                Spacer()
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
    
    private func getTempName(for mediaType: MediaType, key: String) -> String? {
        return mediaType == .photos ? tempCustomPhotosName[key] : tempCustomVideosName[key]
    }
    
    private func setTempName(for mediaType: MediaType, key: String, value: String?) {
        if mediaType == .photos {
            tempCustomPhotosName[key] = value
        } else {
            tempCustomVideosName[key] = value
        }
    }
    
    private func setVmBucket(for mediaType: MediaType, url: URL, bucket: String) {
        if mediaType == .photos {
            vm.setCustomPhotosBucket(for: url, bucket: bucket)
        } else {
            vm.setCustomVideosBucket(for: url, bucket: bucket)
        }
    }

    private func bucketPicker(for url: URL, volumeKey: String, currentBucket: String, isCustomSaved: Bool, mediaType: MediaType) -> some View {
        Picker("Import Bucket", selection: Binding(
            get: {
                if isCustomSaved {
                    if self.getTempName(for: mediaType, key: volumeKey) == nil {
                        DispatchQueue.main.async {
                            self.setTempName(for: mediaType, key: volumeKey, value: currentBucket)
                        }
                    }
                    return "Custom..."
                }
                return currentBucket
            },
            set: { selectedBucket in
                if selectedBucket != "Custom..." {
                    self.setVmBucket(for: mediaType, url: url, bucket: selectedBucket)
                    self.setTempName(for: mediaType, key: volumeKey, value: nil)
                } else {
                    let initialName = self.getTempName(for: mediaType, key: volumeKey) ?? currentBucket
                    let newCustomName = isCustomSaved ? initialName : "Custom Project"
                    self.setTempName(for: mediaType, key: volumeKey, value: newCustomName)
                    if newCustomName == "Custom Project" {
                        self.setVmBucket(for: mediaType, url: url, bucket: newCustomName)
                    }
                }
            }
        )) {
            ForEach(vm.dropdownBuckets, id: \.self) { bucketName in
                Text(bucketName).tag(bucketName)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .tint(.accentPrimary)
    }
    
    private func customFolderInput(for url: URL, volumeKey: String, currentBucket: String, isCustomSaved: Bool, mediaType: MediaType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill.badge.gearshape")
                .foregroundColor(.accentPrimary)
                .font(.caption)
            
            TextField("Enter custom folder name", text: Binding(
                get: {
                    return self.getTempName(for: mediaType, key: volumeKey) ?? (isCustomSaved ? currentBucket : "Custom Project")
                },
                set: { newValue in
                    self.setTempName(for: mediaType, key: volumeKey, value: newValue)
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
                if let newBucket = self.getTempName(for: mediaType, key: volumeKey), !newBucket.isEmpty {
                    self.setVmBucket(for: mediaType, url: url, bucket: newBucket)
                } else {
                    self.setVmBucket(for: mediaType, url: url, bucket: "Custom Project")
                    self.setTempName(for: mediaType, key: volumeKey, value: "Custom Project")
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}
