//
//  ViewController.swift
//  GlamLabTest
//
//  Created by Илья Филяев on 06.02.2023.
//

import UIKit
import CoreML
import Vision
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var imFirst: UIImageView!
    @IBOutlet weak var imSecond: UIImageView!
    @IBOutlet weak var btMain: UIButton!
    
    var imagesArray = [UIImage]()
    var backgroundMusic: AVAudioPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupImages()
        updateUI()
    }
    
    // initial setup UI
    func updateUI() {
        imFirst.image = imagesArray.last
    }
    
    // start slide show
    func startSlideShow() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            self.playAudio()

            for image in self.imagesArray {
                for i in 0..<2 {
                    if i == 0 {
                        sleep(1)
                        DispatchQueue.main.async {
                            self.imSecond.image = image.removeBackground()
                        }
                    } else {
                        sleep(1)
                        DispatchQueue.main.async {
                            self.imFirst.image = image
                            self.imSecond.image = nil
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.btMain.isHidden = false
            }
        }
    }

    func setupImages() {
        for i in 1...8 {
            guard let image = UIImage(named: String(i)) else { return }
            imagesArray.append(image)
        }
    }
    
    func playAudio() {
        guard let url = Bundle.main.url(forResource: "music", withExtension: "aac") else { return }

        do {
            backgroundMusic = try AVAudioPlayer(contentsOf: url)
            backgroundMusic?.play()
        } catch {
            print("Cant play audio")
        }
    }
    
    @IBAction func clickButton(_ sender: UIButton) {
        btMain.isHidden = true
        startSlideShow()
    }
}
