# 数学公式与查找测试

## 行内公式（反斜杠定界符）

质能方程 \(E = mc^2\) 是物理学中最著名的公式之一。
欧拉恒等式 \(e^{i\pi} + 1 = 0\) 被誉为最美公式。

## 行内公式（美元定界符）

勾股定理 $a^2 + b^2 = c^2$ 人人皆知。
求和 $\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}$ 由欧拉求得。

## 独立公式（display）

高斯积分：

\[
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
\]

矩阵形式：

\[
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
\begin{pmatrix} x \\ y \end{pmatrix}
=
\begin{pmatrix} ax + by \\ cx + dy \end{pmatrix}
\]

麦克斯韦方程组之一：

\[
\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}
\]

## 查找测试用文本

关键词：MARKER 出现在这里。
第二个 MARKER 在下一段出现。
大小写测试：marker 小写版本。

## 代码块里的公式不应被渲染

```latex
\(E = mc^2\)  -- 代码块内保持原样
```

## 普通文本

这段没有任何公式，用于验证查找高亮的稳定性。
