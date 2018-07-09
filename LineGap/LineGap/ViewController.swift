//
//  ViewController.swift
//  LineGap
//
//  Created by 杨静伟 on 2018/6/12.
//  Copyright © 2018年 firstleap. All rights reserved.
//

import UIKit
import SceneKit
import AVFoundation

class ViewController: UIViewController {

  @IBOutlet weak var startRecordBtn: UIButton!
  @IBOutlet weak var startPlayBtn: UIButton!
  @IBOutlet weak var tipLabel: UILabel!
  @IBOutlet weak var volumLabel: UILabel!
  
  // 播放器
  var player: AVAudioPlayer?
  var path: String?
  
  override func viewDidLoad() {
    super.viewDidLoad()
  }
  
  @IBAction func startRecord(_ sender: UIButton) {
    sender.isSelected = !sender.isSelected
    if sender.isSelected {
      sender.setTitle("停止", for: .normal)
      RecorderManager.sharedRecorder().delegate = self
      RecorderManager.sharedRecorder().startRecording()
    } else {
      sender.setTitle("开始", for: .normal)
      RecorderManager.sharedRecorder().stopRecording()
    }
    
  }
  
  @IBAction func startPlay(_ sender: UIButton) {
    sender.isSelected = !sender.isSelected
    if sender.isSelected {
      sender.setTitle("停止", for: .normal)
    guard let path = path else {return}
      let url = URL.init(fileURLWithPath: path)
      if player?.url == url {
        player?.play()
        return
      }
      do {
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
        player?.delegate = self
        
      } catch {
        print(error)
        return
      }
    } else {
      sender.setTitle("播放", for: .normal)
      player?.stop()
    }
  }

}
extension ViewController: RecorderMangerDelegate {
  func audioTool(_ manager: RecorderManager!, recorderDidReceivedPcmData pcmData: Data!) {
    print("原始PCM数据")
    tipLabel.text = "data数据大小：\(pcmData.count) \n"
  }
  
  func audioTool(_ manager: RecorderManager!, volume: Int) {
    print("录音音量")
    volumLabel.text = "录音音量:\(volume)"
  }
  
  func audioTool(_ manager: RecorderManager!, filePath path: String!) {
    print(path)
    self.path = path
    let dataStr = tipLabel.text ?? "原始数据"
    let volumeStr = volumLabel.text ?? "录音大小"
    
    tipLabel.text = dataStr + "\n" + volumeStr + "\n" + "path:\(path)"
  }
  
  
}
extension ViewController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    print("播放完成")
    startPlayBtn.setTitle("播放", for: .normal)
    startPlayBtn.isSelected = false
  }
}
